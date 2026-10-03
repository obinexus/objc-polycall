#import <Foundation/Foundation.h>

#include <stdint.h>

/*
 * objc-polycall -- Objective-C / Foundation binding of the Polycall binding
 * ABI v1 (<polycall.h>, libpolycall). Every method calls the C function of
 * the same name in the core; nothing here parses configuration or talks to
 * the network itself.
 *
 * The sources build with clang + ARC (Apple Foundation, or GNUstep with
 * libobjc2) and with GCC + manual reference counting (GNUstep with the GCC
 * runtime, the Debian/Ubuntu default).
 */

/* Nullability annotations only where the compiler knows them (GCC does not). */
#if defined(__has_feature)
#  if __has_feature(nullability)
#    define OBN_NULLABLE _Nullable
#  endif
#endif
#ifndef OBN_NULLABLE
#  define OBN_NULLABLE
#endif

NS_ASSUME_NONNULL_BEGIN

/** NSError domain of every error this binding reports. NSError.code is the
 *  Polycall status (0 = POLYCALL_OK, negative = POLYCALL_E_*). */
FOUNDATION_EXPORT NSString * const OBNPolycallErrorDomain;
/** userInfo: NSString, polycall_strerror(status), e.g. "POLYCALL_E_TIMEOUT: deadline exceeded". */
FOUNDATION_EXPORT NSString * const OBNPolycallStatusNameKey;
/** userInfo: NSString, polycall_last_error() read on the failing thread. */
FOUNDATION_EXPORT NSString * const OBNPolycallDetailKey;
/** userInfo: NSString, the remote error object JSON a failed call returned. */
FOUNDATION_EXPORT NSString * const OBNPolycallRemoteErrorKey;
/** userInfo: NSNumber, bytes the core asked for after POLYCALL_E_TOO_LARGE. */
FOUNDATION_EXPORT NSString * const OBNPolycallRequiredSizeKey;

/* Binding ABI v1 status codes (POLYCALL_OK / POLYCALL_E_* in polycall.h). */
enum {
    OBNPolycallStatusOK = 0,
    OBNPolycallStatusInvalidArgument = -1,
    OBNPolycallStatusNoMemory = -2,
    OBNPolycallStatusInvalidHandle = -3,
    OBNPolycallStatusTimeout = -4,
    OBNPolycallStatusTransport = -5,
    OBNPolycallStatusProtocol = -6,
    OBNPolycallStatusNotFound = -7,
    OBNPolycallStatusAuth = -8,
    OBNPolycallStatusRemote = -9,
    OBNPolycallStatusTooLarge = -10,
    OBNPolycallStatusBusy = -11,
    OBNPolycallStatusCancelled = -12,
    OBNPolycallStatusConfig = -13,
    OBNPolycallStatusAddressInUse = -14,
    OBNPolycallStatusUnsupported = -15,
    OBNPolycallStatusPermission = -16,
    OBNPolycallStatusClosed = -17,
    OBNPolycallStatusInternal = -18
};

/** POLYCALL_PEER_MAX_PAYLOAD / POLYCALL_CALL_MAX_OUTPUT (1 MiB). */
#define OBNPolycallMaxPayload ((NSUInteger)1 << 20)
#define OBNPolycallMaxCallOutput ((NSUInteger)1 << 20)
/** UINT32_MAX: wait until a message, -cancel: or -close:. */
#define OBNPolycallWaitForever ((uint32_t)0xFFFFFFFFu)

@interface OBNPolycall : NSObject

/* ---- library / ABI ---- */

/** polycall_ffi_abi_version() of the loaded library. */
+ (int)abiVersion;
/** The binding ABI this binding was written for (1). */
+ (int)requiredABIVersion;
/** polycall_ffi_version(), e.g. @"1.1.0". */
+ (NSString *)libraryVersion;
/** Path of the loaded libpolycall when the platform can tell (dladdr). */
+ (NSString * OBN_NULLABLE)libraryPath;
/** NO (with an NSError naming the library and both ABI numbers) unless the
 *  loaded library implements binding ABI 1. Every other API checks this. */
+ (BOOL)checkABIVersion:(NSError * OBN_NULLABLE * OBN_NULLABLE)error;
/** polycall_strerror(status). */
+ (NSString *)nameForStatus:(int)status;
/** polycall_last_error() for the calling thread. */
+ (NSString *)lastErrorDetail;
/** NSError for a failed core call (status, name, detail). Call it on the
 *  failing thread before any other Polycall call. */
+ (NSError *)errorForStatus:(int)status;

/* ---- configuration ---- */

/** The documented entry point: exact status of polycall_ffi_run_config(path, 1). */
+ (int32_t)rawStatusForConfigAtPath:(NSString *)configPath;
/** Exact status of polycall_ffi_run_config(path, strict ? 1 : 0). */
+ (int32_t)rawStatusForConfigAtPath:(NSString *)configPath strict:(BOOL)strict;
/** YES for POLYCALL_OK; NO with an NSError otherwise (strict, run = 1). */
+ (BOOL)runConfigAtPath:(NSString *)configPath
                  error:(NSError * OBN_NULLABLE * OBN_NULLABLE)error;
/** Lenient (strict = NO) validation reports unknown keys as warnings; strict
 *  validation rejects them and settings this build cannot honour
 *  (tls_enabled=true -> POLYCALL_E_UNSUPPORTED). */
+ (BOOL)runConfigAtPath:(NSString *)configPath
                 strict:(BOOL)strict
                  error:(NSError * OBN_NULLABLE * OBN_NULLABLE)error;
/** polycall_ffi_describe(): JSON description of a configuration file. */
+ (NSString * OBN_NULLABLE)describeConfigAtPath:(NSString *)configPath
                                          error:(NSError * OBN_NULLABLE * OBN_NULLABLE)error;

/* ---- RPC ---- */

/** One polycall_rpc v1 round trip (polycall_call), executed once, never
 *  retried. Returns the operation's output JSON. inputJSON nil sends null;
 *  timeoutMs must be 1..600000. On failure the NSError carries the remote
 *  error object under OBNPolycallRemoteErrorKey when the core supplied one. */
+ (NSString * OBN_NULLABLE)callEndpoint:(NSString *)endpoint
                                service:(NSString *)service
                              operation:(NSString *)operation
                              inputJSON:(NSString * OBN_NULLABLE)inputJSON
                              timeoutMs:(uint32_t)timeoutMs
                                  error:(NSError * OBN_NULLABLE * OBN_NULLABLE)error;
/** Same with an explicit output buffer size (a too-small buffer discards a
 *  result that already ran: POLYCALL_E_TOO_LARGE + OBNPolycallRequiredSizeKey). */
+ (NSString * OBN_NULLABLE)callEndpoint:(NSString *)endpoint
                                service:(NSString *)service
                              operation:(NSString *)operation
                              inputJSON:(NSString * OBN_NULLABLE)inputJSON
                              timeoutMs:(uint32_t)timeoutMs
                         outputCapacity:(NSUInteger)outputCapacity
                                  error:(NSError * OBN_NULLABLE * OBN_NULLABLE)error;

@end

/** One message taken from a peer node's inbox. */
@interface OBNPolycallMessage : NSObject
{
    NSString *_sender;
    NSString *_messageID;
    NSData *_payload;
}
@property (readonly, copy) NSString *sender;     /* sender node id */
@property (readonly, copy) NSString *messageID;  /* message id */
@property (readonly, copy) NSData *payload;      /* exact bytes (may contain NULs) */
- (instancetype)initWithSender:(NSString *)sender messageID:(NSString *)messageID payload:(NSData *)payload;
/** The payload decoded as UTF-8, or nil when it is not valid UTF-8. */
- (NSString * OBN_NULLABLE)text;
@end

/**
 * A Polycall peer node (polycall_peer_*, protocol polycall-peer/1). The
 * registry and inbox belong to this node only. All methods are thread-safe.
 *
 * -close: stops the listener, wakes blocked receives (POLYCALL_E_CLOSED) and
 * releases the handle; a second -close: or any call after it fails with the
 * core's POLYCALL_E_INVALID_HANDLE. A node that was never closed explicitly
 * is closed exactly once when it is deallocated.
 */
@interface OBNPolycallPeer : NSObject
{
    int32_t _handle;
    BOOL _closedByOwner;
    NSLock *_lock;
}

/** polycall_peer_open. bindEndpoint "127.0.0.1:0" = ephemeral port, nil =
 *  send-only node; authToken nil/empty = no authentication. */
+ (instancetype OBN_NULLABLE)peerWithNodeID:(NSString *)nodeID
                               bindEndpoint:(NSString * OBN_NULLABLE)bindEndpoint
                                  authToken:(NSString * OBN_NULLABLE)authToken
                                      error:(NSError * OBN_NULLABLE * OBN_NULLABLE)error;
- (instancetype OBN_NULLABLE)initWithNodeID:(NSString *)nodeID
                               bindEndpoint:(NSString * OBN_NULLABLE)bindEndpoint
                                  authToken:(NSString * OBN_NULLABLE)authToken
                                      error:(NSError * OBN_NULLABLE * OBN_NULLABLE)error;

/** The core's handle (polycall_peer_t, > 0). */
- (int32_t)handle;
/** Whether -close: has been called on this object. */
- (BOOL)isClosed;

- (BOOL)close:(NSError * OBN_NULLABLE * OBN_NULLABLE)error;
/** Bound "host:port" (@"" for a send-only node). */
- (NSString * OBN_NULLABLE)endpoint:(NSError * OBN_NULLABLE * OBN_NULLABLE)error;
- (NSString * OBN_NULLABLE)nodeID:(NSError * OBN_NULLABLE * OBN_NULLABLE)error;
/** Add or replace peerID -> endpoint in THIS node's registry. */
- (BOOL)registerPeer:(NSString *)peerID endpoint:(NSString *)endpoint
               error:(NSError * OBN_NULLABLE * OBN_NULLABLE)error;
/** POLYCALL_E_NOT_FOUND when peerID is not registered. */
- (BOOL)unregisterPeer:(NSString *)peerID error:(NSError * OBN_NULLABLE * OBN_NULLABLE)error;
/** This node's registry as the core's JSON text / as a dictionary. */
- (NSString * OBN_NULLABLE)registryJSON:(NSError * OBN_NULLABLE * OBN_NULLABLE)error;
- (NSDictionary * OBN_NULLABLE)registry:(NSError * OBN_NULLABLE * OBN_NULLABLE)error;
/** GET /health of peer (registered id or "host:port"). */
- (BOOL)ping:(NSString *)peer timeoutMs:(uint32_t)timeoutMs
       error:(NSError * OBN_NULLABLE * OBN_NULLABLE)error;
/** Exactly one delivery attempt (<= 1 MiB). YES means the receiver stored and
 *  acknowledged it; on POLYCALL_E_TIMEOUT retry with the SAME messageID.
 *  messageID nil lets the core generate one. */
- (BOOL)sendData:(NSData *)payload toPeer:(NSString *)peer
       messageID:(NSString * OBN_NULLABLE)messageID timeoutMs:(uint32_t)timeoutMs
           error:(NSError * OBN_NULLABLE * OBN_NULLABLE)error;
/** Send the UTF-8 bytes of text. */
- (BOOL)sendString:(NSString *)text toPeer:(NSString *)peer
         messageID:(NSString * OBN_NULLABLE)messageID timeoutMs:(uint32_t)timeoutMs
             error:(NSError * OBN_NULLABLE * OBN_NULLABLE)error;
/** Take the oldest message, blocking the calling thread. timeoutMs 0 polls,
 *  OBNPolycallWaitForever waits until a message, -cancel: or -close:. */
- (OBNPolycallMessage * OBN_NULLABLE)receiveWithTimeoutMs:(uint32_t)timeoutMs
                                                    error:(NSError * OBN_NULLABLE * OBN_NULLABLE)error;
/** Same with an explicit payload buffer: a smaller next payload fails with
 *  POLYCALL_E_TOO_LARGE (OBNPolycallRequiredSizeKey) and stays queued. */
- (OBNPolycallMessage * OBN_NULLABLE)receiveWithTimeoutMs:(uint32_t)timeoutMs
                                                 capacity:(NSUInteger)capacity
                                                    error:(NSError * OBN_NULLABLE * OBN_NULLABLE)error;
/** Wake every receive currently blocked on this node (POLYCALL_E_CANCELLED). */
- (BOOL)cancel:(NSError * OBN_NULLABLE * OBN_NULLABLE)error;
/** This node's health JSON. */
- (NSString * OBN_NULLABLE)healthJSON:(NSError * OBN_NULLABLE * OBN_NULLABLE)error;
@end

NS_ASSUME_NONNULL_END
