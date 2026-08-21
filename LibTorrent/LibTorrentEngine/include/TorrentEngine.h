#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TKFile : NSObject
@property (nonatomic, readonly) NSInteger index;
@property (nonatomic, readonly, copy) NSString *path;
@property (nonatomic, readonly) long long offset;
@property (nonatomic, readonly) long long length;
@end

@interface TKStats : NSObject
@property (nonatomic, readonly) double downloadRate;   // bytes/sec (payload)
@property (nonatomic, readonly) NSInteger numPeers;
@property (nonatomic, readonly) NSInteger numSeeds;
@property (nonatomic, readonly) double progress;       // 0…1 over wanted bytes
@property (nonatomic, readonly) long long downloadedBytes;
@end

@interface TKSwarmDiag : NSObject
@property (nonatomic, readonly) NSInteger numPeers;          // connected (payload-capable)
@property (nonatomic, readonly) NSInteger numSeeds;
@property (nonatomic, readonly) NSInteger numConnections;    // incl. handshaking; >= numPeers
@property (nonatomic, readonly) NSInteger connectCandidates; // known peers eligible to try now
@property (nonatomic, readonly) NSInteger listPeers;         // peers known to the peer list
@property (nonatomic, readonly) NSInteger listSeeds;
@property (nonatomic, readonly, copy) NSString *torrentState; // downloading/finished/seeding/…
@property (nonatomic, readonly) long long totalWanted;       // bytes selected for download
@property (nonatomic, readonly) long long totalWantedDone;
@property (nonatomic, readonly) long long allTimeDownload;
@property (nonatomic, readonly) double downloadRate;         // payload bytes/sec
@property (nonatomic, readonly) double uploadRate;
@property (nonatomic, readonly) long long outgoingAttempts;  // TCP SYNs sent to peers
@property (nonatomic, readonly) long long incomingAccepts;
@property (nonatomic, readonly) long long connectFailures;   // failed at the TCP connect stage
@property (nonatomic, readonly) NSInteger dhtNodes;          // DHT routing-table size
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSNumber *> *disconnectReasons;
@property (nonatomic, readonly, copy) NSString *lastPeerSource;
@end

@interface TorrentEngine : NSObject

- (instancetype)initWithSaveDirectory:(NSString *)saveDirectory
                             maxPeers:(NSInteger)maxPeers
                        extraTrackers:(NSArray<NSString *> *)extraTrackers;

- (void)startMagnet:(NSString *)magnetURI resumeData:(nullable NSData *)resumeData;

- (void)retryMetadataDiscovery;

@property (nonatomic, readonly) BOOL isActive;

@property (nonatomic, copy, nullable) void (^onMetadata)(void);
@property (nonatomic, copy, nullable) void (^onPieceFinished)(NSInteger pieceIndex);

@property (nonatomic, readonly) BOOL hasMetadata;
- (NSArray<TKFile *> *)files;
@property (nonatomic, readonly) NSInteger pieceLength;
@property (nonatomic, readonly) NSInteger pieceCount;

- (void)selectFile:(NSInteger)fileIndex;

- (void)prepareStreamingForFile:(NSInteger)fileIndex;
- (void)beginStreamingSteadyStateForFile:(NSInteger)fileIndex;

- (BOOL)hasPiece:(NSInteger)pieceIndex;
- (void)readPiece:(NSInteger)pieceIndex completion:(void (^)(NSData * _Nullable))completion NS_SWIFT_DISABLE_ASYNC;
- (void)setPieceDeadline:(NSInteger)pieceIndex milliseconds:(NSInteger)ms;
- (void)clearPieceDeadline:(NSInteger)pieceIndex;
- (void)setPiecePriority:(NSInteger)pieceIndex priority:(NSInteger)priority;

- (TKStats *)stats;
- (TKSwarmDiag *)diagnostics;

- (void)saveResumeDataWithCompletionHandler:(void (^)(NSData * _Nullable))completionHandler;

- (void)pause;
- (void)resume;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
