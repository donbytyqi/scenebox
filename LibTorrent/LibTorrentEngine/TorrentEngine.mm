#import "TorrentEngine.h"

#include <libtorrent/session.hpp>
#include <libtorrent/session_params.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/torrent_info.hpp>
#include <libtorrent/torrent_status.hpp>
#include <libtorrent/torrent_flags.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/alert_types.hpp>
#include <libtorrent/read_resume_data.hpp>
#include <libtorrent/write_resume_data.hpp>
#include <libtorrent/download_priority.hpp>
#include <libtorrent/file_storage.hpp>
#include <libtorrent/info_hash.hpp>
#include <libtorrent/sha1_hash.hpp>
#include <libtorrent/error_code.hpp>
#include <libtorrent/operations.hpp>
#include <libtorrent/session_stats.hpp>

#include <atomic>
#include <memory>
#include <mutex>
#include <vector>
#include <string>

#include <sys/resource.h>

namespace lt = libtorrent;

#pragma mark - Value types

@implementation TKFile
- (instancetype)initWithIndex:(NSInteger)index path:(NSString *)path
                       offset:(long long)offset length:(long long)length {
    if ((self = [super init])) {
        _index = index; _path = [path copy]; _offset = offset; _length = length;
    }
    return self;
}
@end

@implementation TKStats
- (instancetype)initWithRate:(double)rate peers:(NSInteger)peers seeds:(NSInteger)seeds
                    progress:(double)progress downloaded:(long long)downloaded {
    if ((self = [super init])) {
        _downloadRate = rate; _numPeers = peers; _numSeeds = seeds;
        _progress = progress; _downloadedBytes = downloaded;
    }
    return self;
}
@end

@interface TKSwarmDiag ()
@property (nonatomic, readwrite) NSInteger numPeers, numSeeds, numConnections,
    connectCandidates, listPeers, listSeeds, dhtNodes;
@property (nonatomic, readwrite, copy) NSString *torrentState;
@property (nonatomic, readwrite) long long totalWanted, totalWantedDone, allTimeDownload,
    outgoingAttempts, incomingAccepts, connectFailures;
@property (nonatomic, readwrite) double downloadRate, uploadRate;
@property (nonatomic, readwrite, copy) NSDictionary<NSString *, NSNumber *> *disconnectReasons;
@property (nonatomic, readwrite, copy) NSString *lastPeerSource;
@end
@implementation TKSwarmDiag
- (instancetype)init {
    if ((self = [super init])) {
        _torrentState = @"";
        _disconnectReasons = @{};
        _lastPeerSource = @"";
    }
    return self;
}
@end

static NSString *StateName(lt::torrent_status::state_t s) {
    switch (s) {
        case lt::torrent_status::checking_files: return @"checking_files";
        case lt::torrent_status::downloading_metadata: return @"downloading_metadata";
        case lt::torrent_status::downloading: return @"downloading";
        case lt::torrent_status::finished: return @"finished";
        case lt::torrent_status::seeding: return @"seeding";
        case lt::torrent_status::checking_resume_data: return @"checking_resume_data";
        default: return @"unknown";
    }
}

#pragma mark - Helpers

static NSString *HashKey(const lt::info_hash_t &ih) {
    lt::sha1_hash h = ih.get_best();
    static const char *hex = "0123456789abcdef";
    char buf[41];
    for (int i = 0; i < 20; i++) {
        std::uint8_t b = h[i];
        buf[i * 2] = hex[(b >> 4) & 0xF];
        buf[i * 2 + 1] = hex[b & 0xF];
    }
    buf[40] = 0;
    return [NSString stringWithUTF8String:buf];
}

#pragma mark - TorrentEngine internal hooks (called by the shared session's router)

@interface TorrentEngine ()
- (void)_onMetadataReady;
- (void)_onPieceFinished:(NSInteger)pieceIndex;
- (void)_onResumeData:(nullable NSData *)data;
- (void)_onPieceRead:(NSInteger)pieceIndex data:(nullable NSData *)data;
@property (nonatomic) lt::torrent_handle handle;
@end

#pragma mark - Shared session

@interface LTSharedSession : NSObject
+ (instancetype)shared;
- (lt::torrent_handle)addTorrent:(lt::add_torrent_params)params
                       forEngine:(TorrentEngine *)engine;
- (void)removeEngineForKey:(NSString *)key handle:(lt::torrent_handle)handle
                    engine:(TorrentEngine *)engine;
- (void)saveState;
- (void)fillSessionDiag:(TKSwarmDiag *)diag;
@end

@implementation LTSharedSession {
    std::unique_ptr<lt::session> _session;
    dispatch_queue_t _alertQueue;
    NSMapTable<NSString *, TorrentEngine *> *_engines;   // strong key → weak engine
    dispatch_source_t _saveTimer;

    std::atomic<long long> _outgoingAttempts;
    std::atomic<long long> _incomingAccepts;
    std::atomic<long long> _connectFailures;
    std::atomic<int> _dhtNodes;
    int _dhtNodesIdx;                                    // index into session_stats counters
    NSMutableDictionary<NSString *, NSNumber *> *_disconnectReasons;  // @synchronized(self)
    NSString *_lastPeerSource;                                        // @synchronized(self)
}

+ (instancetype)shared {
    static LTSharedSession *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[LTSharedSession alloc] init]; });
    return instance;
}

- (NSString *)stateFilePath {
    NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    return [dirs.firstObject stringByAppendingPathComponent:@"lt-session.state"];
}

- (instancetype)init {
    if ((self = [super init])) {
        _engines = [NSMapTable strongToWeakObjectsMapTable];
        _alertQueue = dispatch_queue_create("watchbox.libtorrent.alerts", DISPATCH_QUEUE_SERIAL);
        _disconnectReasons = [NSMutableDictionary dictionary];
        _lastPeerSource = @"";
        _dhtNodesIdx = lt::find_metric_idx("dht.dht_nodes");

        struct rlimit rl;
        if (getrlimit(RLIMIT_NOFILE, &rl) == 0) {
            rl.rlim_cur = rl.rlim_max == RLIM_INFINITY ? 8192 : rl.rlim_max;
            setrlimit(RLIMIT_NOFILE, &rl);
        }

        lt::session_params params;
        NSData *saved = [NSData dataWithContentsOfFile:[self stateFilePath]];
        if (saved.length > 0) {
            try {
                std::vector<char> buf((const char *)saved.bytes,
                                      (const char *)saved.bytes + saved.length);
                params = lt::read_session_params(buf);
            } catch (...) { params = lt::session_params(); }
        }

        lt::settings_pack &sp = params.settings;
        sp.set_int(lt::settings_pack::alert_mask,
                   lt::alert_category::status
                   | lt::alert_category::piece_progress
                   | lt::alert_category::storage
                   | lt::alert_category::error
                   | lt::alert_category::connect
                   | lt::alert_category::tracker);
        sp.set_str(lt::settings_pack::user_agent, "WatchBox/1.0 libtorrent/2.0");
        sp.set_bool(lt::settings_pack::enable_dht, true);
        sp.set_bool(lt::settings_pack::enable_lsd, false);
        sp.set_bool(lt::settings_pack::enable_upnp, false);
        sp.set_bool(lt::settings_pack::enable_natpmp, false);
        sp.set_str(lt::settings_pack::listen_interfaces, "0.0.0.0:0,[::]:0");
        sp.set_str(lt::settings_pack::outgoing_interfaces, "");
        sp.set_int(lt::settings_pack::connections_limit, 150);
        sp.set_str(lt::settings_pack::dht_bootstrap_nodes,
                   "router.bittorrent.com:6881,dht.transmissionbt.com:6881,router.utorrent.com:6881,dht.libtorrent.org:25401");

        sp.set_int(lt::settings_pack::torrent_connect_boost, 20);
        sp.set_int(lt::settings_pack::connection_speed, 10);
        sp.set_int(lt::settings_pack::peer_timeout, 30);
        sp.set_int(lt::settings_pack::handshake_timeout, 20);
        sp.set_int(lt::settings_pack::max_out_request_queue, 1500);
        sp.set_int(lt::settings_pack::max_allowed_in_request_queue, 2000);
        sp.set_int(lt::settings_pack::request_queue_time, 5);
        sp.set_int(lt::settings_pack::whole_pieces_threshold, 20);
        sp.set_bool(lt::settings_pack::enable_outgoing_utp, false);
        sp.set_bool(lt::settings_pack::enable_incoming_utp, false);
        sp.set_bool(lt::settings_pack::enable_outgoing_tcp, true);
        sp.set_bool(lt::settings_pack::enable_incoming_tcp, true);
        sp.set_bool(lt::settings_pack::announce_to_all_trackers, true);
        sp.set_bool(lt::settings_pack::announce_to_all_tiers, true);
        sp.set_int(lt::settings_pack::peer_connect_timeout, 8);

        _session = std::make_unique<lt::session>(std::move(params));

        __weak LTSharedSession *weakSelf = self;
        _session->set_alert_notify([weakSelf]{
            __strong LTSharedSession *strongSelf = weakSelf;
            if (!strongSelf) return;
            dispatch_async(strongSelf->_alertQueue, ^{ [strongSelf drainAlerts]; });
        });

        _saveTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                            dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
        dispatch_source_set_timer(_saveTimer, dispatch_time(DISPATCH_TIME_NOW, 45 * NSEC_PER_SEC),
                                  45 * NSEC_PER_SEC, 5 * NSEC_PER_SEC);
        dispatch_source_set_event_handler(_saveTimer, ^{ [weakSelf saveState]; });
        dispatch_resume(_saveTimer);
    }
    return self;
}

- (lt::torrent_handle)addTorrent:(lt::add_torrent_params)params forEngine:(TorrentEngine *)engine {
    lt::info_hash_t ih = params.info_hashes;
    lt::error_code ec;
    lt::torrent_handle handle = _session->add_torrent(std::move(params), ec);
    if (ec == lt::errors::duplicate_torrent) {
        handle = _session->find_torrent(ih.get_best());
        ec.clear();
    }
    if (ec || !handle.is_valid()) {
        NSLog(@"[TorrentEngine] add_torrent failed: %s", ec.message().c_str());
        return lt::torrent_handle();
    }
    NSString *key = HashKey(handle.info_hashes());
    @synchronized (_engines) { [_engines setObject:engine forKey:key]; }
    return handle;
}

- (void)removeEngineForKey:(NSString *)key handle:(lt::torrent_handle)handle
                    engine:(TorrentEngine *)engine {
    @synchronized (_engines) {
        TorrentEngine *owner = [_engines objectForKey:key];
        if (owner != engine) return;
        [_engines removeObjectForKey:key];
    }
    if (handle.is_valid()) _session->remove_torrent(handle);   // keep files on disk
}

- (TorrentEngine *)engineForHandle:(const lt::torrent_handle &)handle {
    if (!handle.is_valid()) return nil;
    NSString *key = HashKey(handle.info_hashes());
    @synchronized (_engines) { return [_engines objectForKey:key]; }
}

- (void)drainAlerts {
    if (!_session) return;
    std::vector<lt::alert *> alerts;
    _session->pop_alerts(&alerts);

    for (lt::alert *a : alerts) {
        if (auto *ss = lt::alert_cast<lt::session_stats_alert>(a)) {
            if (_dhtNodesIdx >= 0) {
                auto counters = ss->counters();
                _dhtNodes.store((int)counters[(size_t)_dhtNodesIdx], std::memory_order_relaxed);
            }
            continue;
        } else if (auto *pc = lt::alert_cast<lt::peer_connect_alert>(a)) {
            if (pc->direction == lt::peer_connect_alert::direction_t::out) {
                _outgoingAttempts.fetch_add(1, std::memory_order_relaxed);
            } else {
                _incomingAccepts.fetch_add(1, std::memory_order_relaxed);
            }
        } else if (auto *pd = lt::alert_cast<lt::peer_disconnected_alert>(a)) {
            if (pd->op == lt::operation_t::connect) {
                _connectFailures.fetch_add(1, std::memory_order_relaxed);
            }
            NSString *key = [NSString stringWithFormat:@"%s/%s",
                             lt::operation_name(pd->op), pd->error.message().c_str()];
            @synchronized (self) {
                _disconnectReasons[key] = @(_disconnectReasons[key].longLongValue + 1);
            }
        } else if (auto *tr = lt::alert_cast<lt::tracker_reply_alert>(a)) {
            NSString *summary = [NSString stringWithFormat:@"%s → %d peers",
                                 tr->tracker_url(), tr->num_peers];
            @synchronized (self) { _lastPeerSource = summary; }
        } else if (auto *dr = lt::alert_cast<lt::dht_reply_alert>(a)) {
            if (dr->num_peers > 0) {
                NSString *summary = [NSString stringWithFormat:@"dht → %d peers", dr->num_peers];
                @synchronized (self) { _lastPeerSource = summary; }
            }
        }

        auto *ta = dynamic_cast<lt::torrent_alert *>(a);   // base class, alert_cast doesn't apply
        if (!ta) continue;
        TorrentEngine *engine = [self engineForHandle:ta->handle];
        if (!engine) continue;

        if (lt::alert_cast<lt::metadata_received_alert>(a) || lt::alert_cast<lt::add_torrent_alert>(a)) {
            [engine _onMetadataReady];
        } else if (auto *pf = lt::alert_cast<lt::piece_finished_alert>(a)) {
            [engine _onPieceFinished:(NSInteger)static_cast<int>(pf->piece_index)];
        } else if (auto *rd = lt::alert_cast<lt::save_resume_data_alert>(a)) {
            std::vector<char> buf = lt::write_resume_data_buf(rd->params);
            [engine _onResumeData:[NSData dataWithBytes:buf.data() length:buf.size()]];
        } else if (lt::alert_cast<lt::save_resume_data_failed_alert>(a)) {
            [engine _onResumeData:nil];
        } else if (auto *te = lt::alert_cast<lt::torrent_error_alert>(a)) {
            NSLog(@"[TorrentEngine] torrent error: %s", te->error.message().c_str());
        } else if (auto *rp = lt::alert_cast<lt::read_piece_alert>(a)) {
            NSData *data = nil;
            if (!rp->error && rp->buffer) {
                data = [NSData dataWithBytes:rp->buffer.get() length:(NSUInteger)rp->size];
            }
            [engine _onPieceRead:(NSInteger)static_cast<int>(rp->piece) data:data];
        }
    }
}

- (void)fillSessionDiag:(TKSwarmDiag *)diag {
    diag.outgoingAttempts = _outgoingAttempts.load(std::memory_order_relaxed);
    diag.incomingAccepts = _incomingAccepts.load(std::memory_order_relaxed);
    diag.connectFailures = _connectFailures.load(std::memory_order_relaxed);
    diag.dhtNodes = _dhtNodes.load(std::memory_order_relaxed);
    @synchronized (self) {
        diag.disconnectReasons = [_disconnectReasons copy];
        diag.lastPeerSource = _lastPeerSource;
    }
    if (_session) _session->post_session_stats();
}

- (void)saveState {
    if (!_session) return;
    try {
        lt::session_params params = _session->session_state();
        std::vector<char> buf = lt::write_session_params_buf(params);
        NSData *data = [NSData dataWithBytes:buf.data() length:buf.size()];
        [data writeToFile:[self stateFilePath] atomically:YES];
    } catch (...) {}
}

@end

#pragma mark - TorrentEngine (per-torrent facade)

@implementation TorrentEngine {
    std::shared_ptr<const lt::torrent_info> _ti;
    std::mutex _mutex;                 // guards _ti / _hasMetadata / _handle reads
    BOOL _hasMetadata;

    NSString *_saveDir;
    NSArray<NSString *> *_extraTrackers;
    NSInteger _maxPeers;
    NSString *_registryKey;

    std::mutex _resumeMutex;
    void (^_resumeCompletion)(NSData * _Nullable);

    NSMutableDictionary<NSNumber *, NSMutableArray *> *_pieceReads;
}

@synthesize handle = _handle;

- (instancetype)initWithSaveDirectory:(NSString *)saveDirectory
                             maxPeers:(NSInteger)maxPeers
                        extraTrackers:(NSArray<NSString *> *)extraTrackers {
    if ((self = [super init])) {
        _saveDir = [saveDirectory copy];
        _extraTrackers = [extraTrackers copy] ?: @[];
        _maxPeers = maxPeers;
        _hasMetadata = NO;
        _pieceReads = [NSMutableDictionary dictionary];
        (void)[LTSharedSession shared];
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

- (void)startMagnet:(NSString *)magnetURI resumeData:(NSData *)resumeData {
    lt::add_torrent_params atp;
    lt::error_code ec;

    if (resumeData.length > 0) {
        std::vector<char> buf((const char *)resumeData.bytes,
                              (const char *)resumeData.bytes + resumeData.length);
        atp = lt::read_resume_data(buf, ec);
    }
    if (ec || resumeData.length == 0) {
        ec.clear();
        atp = lt::parse_magnet_uri(magnetURI.UTF8String, ec);
        if (ec) { NSLog(@"[TorrentEngine] bad magnet: %s", ec.message().c_str()); return; }
    }

    atp.save_path = _saveDir.UTF8String;
    atp.flags &= ~lt::torrent_flags::paused;
    atp.flags &= ~lt::torrent_flags::auto_managed;
    atp.max_connections = (int)MAX(4, _maxPeers);
    for (NSString *tracker in _extraTrackers) {
        atp.trackers.push_back(std::string(tracker.UTF8String));
    }

    lt::torrent_handle handle = [[LTSharedSession shared] addTorrent:std::move(atp) forEngine:self];
    if (!handle.is_valid()) return;
    {
        std::lock_guard<std::mutex> lock(_mutex);
        _handle = handle;
        _registryKey = HashKey(handle.info_hashes());
    }
    [self _onMetadataReady];
}

- (BOOL)isActive {
    std::lock_guard<std::mutex> lock(_mutex);
    return _handle.is_valid();
}

- (void)retryMetadataDiscovery {
    lt::torrent_handle h;
    { std::lock_guard<std::mutex> lock(_mutex); h = _handle; }
    if (!h.is_valid() || h.torrent_file()) return;
    h.force_reannounce(0);
    h.force_dht_announce();
}

#pragma mark Router hooks

- (void)_onMetadataReady {
    lt::torrent_handle h;
    { std::lock_guard<std::mutex> lock(_mutex); h = _handle; }
    if (!h.is_valid()) return;
    auto ti = h.torrent_file();
    if (!ti) return;
    {
        std::lock_guard<std::mutex> lock(_mutex);
        if (_hasMetadata) return;
        _ti = ti;
        _hasMetadata = YES;
    }
    if (self.onMetadata) self.onMetadata();
}

- (void)_onPieceFinished:(NSInteger)pieceIndex {
    if (self.onPieceFinished) self.onPieceFinished(pieceIndex);
}

- (void)_onResumeData:(NSData *)data {
    void (^completion)(NSData * _Nullable) = nil;
    {
        std::lock_guard<std::mutex> lock(_resumeMutex);
        completion = _resumeCompletion;
        _resumeCompletion = nil;
    }
    if (completion) completion(data);
}

#pragma mark Metadata / files

- (BOOL)hasMetadata {
    std::lock_guard<std::mutex> lock(_mutex);
    return _hasMetadata;
}

- (NSArray<TKFile *> *)files {
    std::shared_ptr<const lt::torrent_info> ti;
    { std::lock_guard<std::mutex> lock(_mutex); ti = _ti; }
    if (!ti) return @[];
    NSMutableArray<TKFile *> *result = [NSMutableArray array];
    lt::file_storage const &fs = ti->files();
    std::string save = _saveDir.UTF8String;
    for (int i = 0; i < fs.num_files(); i++) {
        lt::file_index_t idx{i};
        std::string path = fs.file_path(idx, save);
        [result addObject:[[TKFile alloc]
            initWithIndex:i
                     path:[NSString stringWithUTF8String:path.c_str()]
                   offset:(long long)fs.file_offset(idx)
                   length:(long long)fs.file_size(idx)]];
    }
    return result;
}

- (NSInteger)pieceLength {
    std::lock_guard<std::mutex> lock(_mutex);
    return _ti ? _ti->piece_length() : 0;
}

- (NSInteger)pieceCount {
    std::lock_guard<std::mutex> lock(_mutex);
    return _ti ? _ti->num_pieces() : 0;
}

- (void)selectFile:(NSInteger)fileIndex {
    lt::torrent_handle h;
    std::shared_ptr<const lt::torrent_info> ti;
    { std::lock_guard<std::mutex> lock(_mutex); h = _handle; ti = _ti; }
    if (!h.is_valid() || !ti) return;

    int n = ti->files().num_files();
    std::vector<lt::download_priority_t> priorities(n, lt::dont_download);
    if (fileIndex >= 0 && fileIndex < n) priorities[(size_t)fileIndex] = lt::default_priority;
    h.prioritize_files(priorities);
}

- (void)prepareStreamingForFile:(NSInteger)fileIndex {
    lt::torrent_handle h;
    std::shared_ptr<const lt::torrent_info> ti;
    { std::lock_guard<std::mutex> lock(_mutex); h = _handle; ti = _ti; }
    if (!h.is_valid() || !ti) return;

    int n = ti->files().num_files();
    std::vector<lt::download_priority_t> priorities(n, lt::dont_download);
    if (fileIndex >= 0 && fileIndex < n) priorities[(size_t)fileIndex] = lt::low_priority;
    h.prioritize_files(priorities);
    h.unset_flags(lt::torrent_flags::sequential_download);
}

- (void)beginStreamingSteadyStateForFile:(NSInteger)fileIndex {
    (void)fileIndex;
}

#pragma mark Piece control

- (BOOL)hasPiece:(NSInteger)pieceIndex {
    lt::torrent_handle h;
    { std::lock_guard<std::mutex> lock(_mutex); h = _handle; }
    if (!h.is_valid()) return NO;
    return h.have_piece(lt::piece_index_t{(int)pieceIndex});
}

- (void)readPiece:(NSInteger)pieceIndex completion:(void (^)(NSData * _Nullable))completion {
    lt::torrent_handle h;
    { std::lock_guard<std::mutex> lock(_mutex); h = _handle; }
    if (!h.is_valid()) { completion(nil); return; }
    @synchronized (_pieceReads) {
        NSNumber *key = @(pieceIndex);
        NSMutableArray *waiters = _pieceReads[key];
        if (!waiters) { waiters = [NSMutableArray array]; _pieceReads[key] = waiters; }
        [waiters addObject:[completion copy]];
    }
    h.read_piece(lt::piece_index_t{(int)pieceIndex});
}

- (void)_onPieceRead:(NSInteger)pieceIndex data:(NSData *)data {
    NSArray *completions;
    @synchronized (_pieceReads) {
        NSNumber *key = @(pieceIndex);
        completions = _pieceReads[key];
        [_pieceReads removeObjectForKey:key];
    }
    for (void (^completion)(NSData * _Nullable) in completions) { completion(data); }
}

- (void)setPieceDeadline:(NSInteger)pieceIndex milliseconds:(NSInteger)ms {
    lt::torrent_handle h;
    { std::lock_guard<std::mutex> lock(_mutex); h = _handle; }
    if (!h.is_valid()) return;
    h.set_piece_deadline(lt::piece_index_t{(int)pieceIndex}, (int)ms);
}

- (void)clearPieceDeadline:(NSInteger)pieceIndex {
    lt::torrent_handle h;
    { std::lock_guard<std::mutex> lock(_mutex); h = _handle; }
    if (!h.is_valid()) return;
    h.reset_piece_deadline(lt::piece_index_t{(int)pieceIndex});
}

- (void)setPiecePriority:(NSInteger)pieceIndex priority:(NSInteger)priority {
    lt::torrent_handle h;
    { std::lock_guard<std::mutex> lock(_mutex); h = _handle; }
    if (!h.is_valid()) return;
    h.piece_priority(lt::piece_index_t{(int)pieceIndex},
                     lt::download_priority_t{(std::uint8_t)MAX(0, MIN(7, priority))});
}

#pragma mark Stats

- (TKStats *)stats {
    lt::torrent_handle h;
    { std::lock_guard<std::mutex> lock(_mutex); h = _handle; }
    if (!h.is_valid()) return [[TKStats alloc] initWithRate:0 peers:0 seeds:0 progress:0 downloaded:0];
    lt::torrent_status st = h.status();
    double progress = st.total_wanted > 0 ? (double)st.total_wanted_done / (double)st.total_wanted : 0.0;
    return [[TKStats alloc] initWithRate:(double)st.download_payload_rate
                                   peers:(NSInteger)st.num_peers
                                   seeds:(NSInteger)st.num_seeds
                                progress:progress
                              downloaded:(long long)st.total_wanted_done];
}

- (TKSwarmDiag *)diagnostics {
    TKSwarmDiag *diag = [[TKSwarmDiag alloc] init];
    lt::torrent_handle h;
    { std::lock_guard<std::mutex> lock(_mutex); h = _handle; }
    if (h.is_valid()) {
        lt::torrent_status st = h.status();
        diag.numPeers = st.num_peers;
        diag.numSeeds = st.num_seeds;
        diag.numConnections = st.num_connections;
        diag.connectCandidates = st.connect_candidates;
        diag.listPeers = st.list_peers;
        diag.listSeeds = st.list_seeds;
        diag.torrentState = StateName(st.state);
        diag.totalWanted = st.total_wanted;
        diag.totalWantedDone = st.total_wanted_done;
        diag.allTimeDownload = st.all_time_download;
        diag.downloadRate = st.download_payload_rate;
        diag.uploadRate = st.upload_payload_rate;
    }
    [[LTSharedSession shared] fillSessionDiag:diag];
    return diag;
}

#pragma mark Resume

- (void)saveResumeDataWithCompletionHandler:(void (^)(NSData * _Nullable))completionHandler {
    lt::torrent_handle h;
    { std::lock_guard<std::mutex> lock(_mutex); h = _handle; }
    if (!h.is_valid()) { completionHandler(nil); return; }

    { std::lock_guard<std::mutex> lock(_resumeMutex); _resumeCompletion = [completionHandler copy]; }
    h.save_resume_data(lt::torrent_handle::save_info_dict);

    __weak TorrentEngine *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [weakSelf _onResumeData:nil];
    });
}

#pragma mark Lifecycle

- (void)pause {
    lt::torrent_handle h;
    { std::lock_guard<std::mutex> lock(_mutex); h = _handle; }
    if (h.is_valid()) h.pause();
}

- (void)resume {
    lt::torrent_handle h;
    { std::lock_guard<std::mutex> lock(_mutex); h = _handle; }
    if (h.is_valid()) h.resume();
}

- (void)stop {
    lt::torrent_handle h;
    NSString *key;
    {
        std::lock_guard<std::mutex> lock(_mutex);
        h = _handle;
        key = _registryKey;
        _handle = lt::torrent_handle();
        _registryKey = nil;
        _ti.reset();
        _hasMetadata = NO;
    }
    if (key) [[LTSharedSession shared] removeEngineForKey:key handle:h engine:self];
    NSArray<NSMutableArray *> *pending;
    @synchronized (_pieceReads) { pending = _pieceReads.allValues; [_pieceReads removeAllObjects]; }
    for (NSMutableArray *waiters in pending) {
        for (void (^completion)(NSData * _Nullable) in waiters) { completion(nil); }
    }
    [[LTSharedSession shared] saveState];
}

@end
