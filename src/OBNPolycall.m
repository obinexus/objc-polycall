#if defined(__linux__) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE 1 /* dladdr, RTLD_DEFAULT */
#endif

#import "OBNPolycall.h"

#include "objc_polycall.h"

/* The core's installed public header (pkg-config --cflags polycall). */
#include <polycall.h>

#include <string.h>
#if !defined(_WIN32)
#include <dlfcn.h>
#endif

/* ARC (clang) and manual reference counting (GCC/GNUstep) from one source. */
#if defined(__has_feature)
#  if __has_feature(objc_arc)
#    define OBN_ARC 1
#  endif
#endif
#ifndef OBN_ARC
#  define OBN_ARC 0
#endif
#if OBN_ARC
#  define OBN_RELEASE(x) ((void)0)
#  define OBN_AUTORELEASE(x) (x)
#else
#  define OBN_RELEASE(x) [(x) release]
#  define OBN_AUTORELEASE(x) [(x) autorelease]
#endif

NSString * const OBNPolycallErrorDomain = @"org.obinexus.polycall";
NSString * const OBNPolycallStatusNameKey = @"OBNPolycallStatusName";
NSString * const OBNPolycallDetailKey = @"OBNPolycallDetail";
NSString * const OBNPolycallRemoteErrorKey = @"OBNPolycallRemoteError";
NSString * const OBNPolycallRequiredSizeKey = @"OBNPolycallRequiredSize";

static NSString *OBNString(const char *text) {
    NSString *s;
    if (text == NULL) {
        return @"";
    }
    s = [NSString stringWithUTF8String:text];
    return s != nil ? s : [NSString stringWithCString:text encoding:NSISOLatin1StringEncoding];
}

static NSError *OBNMakeError(int status, NSString *name, NSString *detail,
                             NSString *remote, NSNumber *required) {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    NSString *description = [detail length] > 0
        ? [NSString stringWithFormat:@"%@ [%d]: %@", name, status, detail]
        : [NSString stringWithFormat:@"%@ [%d]", name, status];
    [info setObject:description forKey:NSLocalizedDescriptionKey];
    [info setObject:name forKey:OBNPolycallStatusNameKey];
    [info setObject:detail forKey:OBNPolycallDetailKey];
    if (remote != nil) {
        [info setObject:remote forKey:OBNPolycallRemoteErrorKey];
    }
    if (required != nil) {
        [info setObject:required forKey:OBNPolycallRequiredSizeKey];
    }
    return [NSError errorWithDomain:OBNPolycallErrorDomain
                               code:(NSInteger)status
                           userInfo:info];
}

/* An error raised by the binding itself, named with the core's vocabulary. */
static NSError *OBNBindingError(int status, NSString *detail) {
    return OBNMakeError(status, OBNString(polycall_strerror(status)), detail, nil, nil);
}

static BOOL OBNFail(NSError **error, NSError *value) {
    if (error != NULL) {
        *error = value;
    }
    return NO;
}

static BOOL OBNCheck(int status, NSError **error) {
    if (status == POLYCALL_OK) {
        return YES;
    }
    return OBNFail(error, [OBNPolycall errorForStatus:status]);
}

/* UTF-8 C string for a required (or, with optional, nil-able) argument. A
 * string containing U+0000 cannot cross the C ABI unchanged: refused. */
static BOOL OBNArg(NSString *value, NSString *what, BOOL optional,
                   const char **out, NSError **error) {
    unichar nul = 0;
    *out = NULL;
    if (value == nil) {
        if (optional) {
            return YES;
        }
        return OBNFail(error, OBNBindingError(POLYCALL_E_INVALID_ARGUMENT,
            [NSString stringWithFormat:@"%@ must not be nil", what]));
    }
    if ([value rangeOfString:[NSString stringWithCharacters:&nul length:1]].location != NSNotFound) {
        return OBNFail(error, OBNBindingError(POLYCALL_E_INVALID_ARGUMENT,
            [NSString stringWithFormat:@"%@ contains a NUL character", what]));
    }
    *out = [value UTF8String];
    if (*out == NULL) {
        return OBNFail(error, OBNBindingError(POLYCALL_E_INVALID_ARGUMENT,
            [NSString stringWithFormat:@"%@ cannot be encoded as UTF-8", what]));
    }
    return YES;
}

typedef int (*OBNTextFill)(int32_t handle, char *buf, size_t cap, size_t *needed);

/* Outputs with an out_len (list, health): grow on POLYCALL_E_TOO_LARGE. */
static NSString *OBNFetchText(int32_t handle, OBNTextFill fill, NSError **error) {
    size_t cap = 4096;
    int attempt;
    for (attempt = 0; attempt < 6; ++attempt) {
        NSMutableData *buf = [NSMutableData dataWithLength:cap];
        size_t needed = 0;
        int status = fill(handle, (char *)[buf mutableBytes], cap, &needed);
        if (status == POLYCALL_OK) {
            return OBNString((const char *)[buf bytes]);
        }
        if (status != POLYCALL_E_TOO_LARGE) {
            OBNFail(error, [OBNPolycall errorForStatus:status]);
            return nil;
        }
        cap = needed + 1 > cap * 2 ? needed + 1 : cap * 2;
    }
    OBNFail(error, OBNBindingError(POLYCALL_E_INTERNAL, @"output kept growing"));
    return nil;
}

@implementation OBNPolycall

+ (int)abiVersion {
    return polycall_ffi_abi_version();
}

+ (int)requiredABIVersion {
    return POLYCALL_FFI_ABI_VERSION;
}

+ (NSString *)libraryVersion {
    char buf[64];
    int n = polycall_ffi_version(buf, (int)sizeof buf);
    if (n >= (int)sizeof buf) {
        NSMutableData *big = [NSMutableData dataWithLength:(NSUInteger)n + 1];
        polycall_ffi_version((char *)[big mutableBytes], n + 1);
        return OBNString((const char *)[big bytes]);
    }
    return OBNString(buf);
}

+ (NSString *)libraryPath {
#if !defined(_WIN32)
    Dl_info info;
    void *symbol = dlsym(RTLD_DEFAULT, "polycall_ffi_abi_version");
    if (symbol != NULL && dladdr(symbol, &info) != 0 && info.dli_fname != NULL) {
        return OBNString(info.dli_fname);
    }
#endif
    return nil;
}

+ (BOOL)checkABIVersion:(NSError **)error {
    int found = polycall_ffi_abi_version();
    NSString *library;
    if (found == POLYCALL_FFI_ABI_VERSION) {
        return YES;
    }
    library = [self libraryPath];
    /* The name is fixed here: an incompatible library's strerror is not trusted. */
    return OBNFail(error, OBNMakeError(POLYCALL_E_UNSUPPORTED,
        @"POLYCALL_E_UNSUPPORTED: binding ABI mismatch",
        [NSString stringWithFormat:@"%@ implements binding ABI %d (library version %@); "
                                   @"objc-polycall requires binding ABI %d",
                                   library != nil ? library : @"libpolycall", found,
                                   [self libraryVersion], POLYCALL_FFI_ABI_VERSION],
        nil, nil));
}

+ (NSString *)nameForStatus:(int)status {
    return OBNString(polycall_strerror(status));
}

+ (NSString *)lastErrorDetail {
    char buf[512];
    int n = polycall_last_error(buf, sizeof buf);
    if (n >= (int)sizeof buf) {
        NSMutableData *big = [NSMutableData dataWithLength:(NSUInteger)n + 1];
        polycall_last_error((char *)[big mutableBytes], (size_t)n + 1);
        return OBNString((const char *)[big bytes]);
    }
    return OBNString(buf);
}

+ (NSError *)errorForStatus:(int)status {
    NSString *detail = [self lastErrorDetail];
    return OBNMakeError(status, [self nameForStatus:status], detail, nil, nil);
}

+ (int32_t)rawStatusForConfigAtPath:(NSString *)configPath {
    return [self rawStatusForConfigAtPath:configPath strict:YES];
}

+ (int32_t)rawStatusForConfigAtPath:(NSString *)configPath strict:(BOOL)strict {
    const char *utf8Path;
    if (configPath == nil) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"configPath must not be nil"
                                     userInfo:nil];
    }
    utf8Path = [configPath UTF8String];
    if (utf8Path == NULL) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"configPath could not be encoded as UTF-8"
                                     userInfo:nil];
    }
    if (polycall_ffi_abi_version() != POLYCALL_FFI_ABI_VERSION) {
        return POLYCALL_E_UNSUPPORTED;
    }
    return strict ? objc_polycall_run_config(utf8Path)
                  : objc_polycall_run_config_strict(utf8Path, 0);
}

+ (BOOL)runConfigAtPath:(NSString *)configPath error:(NSError **)error {
    return [self runConfigAtPath:configPath strict:YES error:error];
}

+ (BOOL)runConfigAtPath:(NSString *)configPath strict:(BOOL)strict error:(NSError **)error {
    const char *path;
    int32_t status;
    if (![self checkABIVersion:error] || !OBNArg(configPath, @"configPath", NO, &path, error)) {
        return NO;
    }
    status = strict ? objc_polycall_run_config(path) : objc_polycall_run_config_strict(path, 0);
    if (status == POLYCALL_OK) {
        return YES;
    }
    if (error != NULL) {
        NSError *base = [self errorForStatus:status];
        NSMutableDictionary *info = [NSMutableDictionary dictionaryWithDictionary:[base userInfo]];
        [info setObject:configPath forKey:@"configPath"];
        *error = [NSError errorWithDomain:OBNPolycallErrorDomain
                                     code:(NSInteger)status
                                 userInfo:info];
    }
    return NO;
}

+ (NSString *)describeConfigAtPath:(NSString *)configPath error:(NSError **)error {
    const char *path;
    int cap = 4096, attempt;
    if (![self checkABIVersion:error] || !OBNArg(configPath, @"configPath", NO, &path, error)) {
        return nil;
    }
    for (attempt = 0; attempt < 4; ++attempt) {
        NSMutableData *buf = [NSMutableData dataWithLength:(NSUInteger)cap];
        int n = polycall_ffi_describe(path, (char *)[buf mutableBytes], cap);
        if (n < 0) {
            OBNFail(error, [self errorForStatus:n]);
            return nil;
        }
        if (n < cap) {
            return OBNString((const char *)[buf bytes]);
        }
        cap = n + 1;
    }
    OBNFail(error, OBNBindingError(POLYCALL_E_INTERNAL, @"describe output kept growing"));
    return nil;
}

+ (NSString *)callEndpoint:(NSString *)endpoint service:(NSString *)service
                 operation:(NSString *)operation inputJSON:(NSString *)inputJSON
                 timeoutMs:(uint32_t)timeoutMs error:(NSError **)error {
    return [self callEndpoint:endpoint service:service operation:operation inputJSON:inputJSON
                    timeoutMs:timeoutMs outputCapacity:OBNPolycallMaxCallOutput + 1 error:error];
}

+ (NSString *)callEndpoint:(NSString *)endpoint service:(NSString *)service
                 operation:(NSString *)operation inputJSON:(NSString *)inputJSON
                 timeoutMs:(uint32_t)timeoutMs outputCapacity:(NSUInteger)outputCapacity
                     error:(NSError **)error {
    const char *ep, *sv, *op, *in;
    NSMutableData *out;
    size_t outLen = 0;
    int status;
    if (![self checkABIVersion:error]
        || !OBNArg(endpoint, @"endpoint", NO, &ep, error)
        || !OBNArg(service, @"service", NO, &sv, error)
        || !OBNArg(operation, @"operation", NO, &op, error)
        || !OBNArg(inputJSON, @"inputJSON", YES, &in, error)) {
        return nil;
    }
    out = [NSMutableData dataWithLength:outputCapacity > 0 ? outputCapacity : 1];
    status = polycall_call(ep, sv, op, in, timeoutMs,
                           outputCapacity > 0 ? (char *)[out mutableBytes] : NULL,
                           outputCapacity, &outLen);
    if (status == POLYCALL_OK) {
        return OBNString((const char *)[out bytes]);
    }
    if (error != NULL) {
        const char *text = (const char *)[out bytes];
        NSString *remote = outputCapacity > 0 && text[0] != '\0' ? OBNString(text) : nil;
        NSString *detail = [self lastErrorDetail];
        *error = OBNMakeError(status, [self nameForStatus:status], detail, remote,
                              status == POLYCALL_E_TOO_LARGE
                                  ? [NSNumber numberWithUnsignedLongLong:(unsigned long long)outLen]
                                  : nil);
    }
    return nil;
}

@end

@implementation OBNPolycallMessage

@synthesize sender = _sender;
@synthesize messageID = _messageID;
@synthesize payload = _payload;

- (instancetype)initWithSender:(NSString *)sender messageID:(NSString *)messageID payload:(NSData *)payload {
    self = [super init];
    if (self != nil) {
        _sender = [sender copy];
        _messageID = [messageID copy];
        _payload = [payload copy];
    }
    return self;
}

- (NSString *)text {
    NSString *s = [[NSString alloc] initWithData:_payload encoding:NSUTF8StringEncoding];
    return OBN_AUTORELEASE(s);
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<OBNPolycallMessage from %@ id %@, %lu bytes>",
                                      _sender, _messageID, (unsigned long)[_payload length]];
}

#if !OBN_ARC
- (void)dealloc {
    [_sender release];
    [_messageID release];
    [_payload release];
    [super dealloc];
}
#endif

@end

@implementation OBNPolycallPeer

+ (instancetype)peerWithNodeID:(NSString *)nodeID bindEndpoint:(NSString *)bindEndpoint
                     authToken:(NSString *)authToken error:(NSError **)error {
    id peer = [[self alloc] initWithNodeID:nodeID bindEndpoint:bindEndpoint
                                 authToken:authToken error:error];
    return OBN_AUTORELEASE(peer);
}

- (instancetype)initWithNodeID:(NSString *)nodeID bindEndpoint:(NSString *)bindEndpoint
                     authToken:(NSString *)authToken error:(NSError **)error {
    const char *cid, *cbind, *ctoken;
    polycall_peer_t handle = 0;
    int status;
    self = [super init];
    if (self == nil) {
        return nil;
    }
    _lock = [[NSLock alloc] init];
    _closedByOwner = YES; /* nothing to release until the open succeeds */
    if (![OBNPolycall checkABIVersion:error]
        || !OBNArg(nodeID, @"nodeID", NO, &cid, error)
        || !OBNArg(bindEndpoint, @"bindEndpoint", YES, &cbind, error)
        || !OBNArg(authToken, @"authToken", YES, &ctoken, error)) {
        OBN_RELEASE(self);
        return nil;
    }
    status = polycall_peer_open(cid, cbind, ctoken, &handle);
    if (status != POLYCALL_OK) {
        OBNFail(error, [OBNPolycall errorForStatus:status]);
        OBN_RELEASE(self);
        return nil;
    }
    _handle = handle;
    _closedByOwner = NO;
    return self;
}

- (void)dealloc {
    if (!_closedByOwner) {
        polycall_peer_close(_handle);
    }
#if !OBN_ARC
    [_lock release];
    [super dealloc];
#endif
}

- (int32_t)handle {
    return _handle;
}

- (BOOL)isClosed {
    BOOL closed;
    [_lock lock];
    closed = _closedByOwner;
    [_lock unlock];
    return closed;
}

- (BOOL)close:(NSError **)error {
    [_lock lock];
    _closedByOwner = YES;
    [_lock unlock];
    return OBNCheck(polycall_peer_close(_handle), error);
}

- (NSString *)endpoint:(NSError **)error {
    char buf[POLYCALL_ENDPOINT_MAX];
    if (!OBNCheck(polycall_peer_endpoint(_handle, buf, sizeof buf), error)) {
        return nil;
    }
    return OBNString(buf);
}

- (NSString *)nodeID:(NSError **)error {
    char buf[POLYCALL_PEER_ID_MAX];
    if (!OBNCheck(polycall_peer_node_id(_handle, buf, sizeof buf), error)) {
        return nil;
    }
    return OBNString(buf);
}

- (BOOL)registerPeer:(NSString *)peerID endpoint:(NSString *)endpoint error:(NSError **)error {
    const char *id_, *ep;
    if (!OBNArg(peerID, @"peerID", NO, &id_, error) || !OBNArg(endpoint, @"endpoint", NO, &ep, error)) {
        return NO;
    }
    return OBNCheck(polycall_peer_register(_handle, id_, ep), error);
}

- (BOOL)unregisterPeer:(NSString *)peerID error:(NSError **)error {
    const char *id_;
    if (!OBNArg(peerID, @"peerID", NO, &id_, error)) {
        return NO;
    }
    return OBNCheck(polycall_peer_unregister(_handle, id_), error);
}

- (NSString *)registryJSON:(NSError **)error {
    return OBNFetchText(_handle, polycall_peer_list, error);
}

- (NSDictionary *)registry:(NSError **)error {
    NSString *json = [self registryJSON:error];
    id object;
    if (json == nil) {
        return nil;
    }
    object = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding]
                                             options:0
                                               error:NULL];
    if (![object isKindOfClass:[NSDictionary class]]) {
        OBNFail(error, OBNBindingError(POLYCALL_E_PROTOCOL,
            [NSString stringWithFormat:@"unexpected registry JSON: %@", json]));
        return nil;
    }
    return object;
}

- (BOOL)ping:(NSString *)peer timeoutMs:(uint32_t)timeoutMs error:(NSError **)error {
    const char *p;
    if (!OBNArg(peer, @"peer", NO, &p, error)) {
        return NO;
    }
    return OBNCheck(polycall_peer_ping(_handle, p, timeoutMs), error);
}

- (BOOL)sendData:(NSData *)payload toPeer:(NSString *)peer messageID:(NSString *)messageID
       timeoutMs:(uint32_t)timeoutMs error:(NSError **)error {
    const char *p, *mid;
    if (payload == nil) {
        return OBNFail(error, OBNBindingError(POLYCALL_E_INVALID_ARGUMENT, @"payload must not be nil"));
    }
    if (!OBNArg(peer, @"peer", NO, &p, error) || !OBNArg(messageID, @"messageID", YES, &mid, error)) {
        return NO;
    }
    return OBNCheck(polycall_peer_send(_handle, p, [payload length] > 0 ? [payload bytes] : NULL,
                                       [payload length], mid, timeoutMs), error);
}

- (BOOL)sendString:(NSString *)text toPeer:(NSString *)peer messageID:(NSString *)messageID
         timeoutMs:(uint32_t)timeoutMs error:(NSError **)error {
    NSData *bytes = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (bytes == nil) {
        return OBNFail(error, OBNBindingError(POLYCALL_E_INVALID_ARGUMENT, @"text cannot be encoded as UTF-8"));
    }
    return [self sendData:bytes toPeer:peer messageID:messageID timeoutMs:timeoutMs error:error];
}

- (OBNPolycallMessage *)receiveWithTimeoutMs:(uint32_t)timeoutMs error:(NSError **)error {
    return [self receiveWithTimeoutMs:timeoutMs capacity:OBNPolycallMaxPayload error:error];
}

- (OBNPolycallMessage *)receiveWithTimeoutMs:(uint32_t)timeoutMs capacity:(NSUInteger)capacity
                                       error:(NSError **)error {
    char sender[POLYCALL_PEER_ID_MAX];
    char messageID[POLYCALL_MESSAGE_ID_MAX];
    NSMutableData *payload = [NSMutableData dataWithLength:capacity > 0 ? capacity : 1];
    size_t length = 0;
    int status;
    OBNPolycallMessage *message;
    sender[0] = '\0';
    messageID[0] = '\0';
    status = polycall_peer_recv(_handle, timeoutMs, sender, sizeof sender, messageID, sizeof messageID,
                                capacity > 0 ? [payload mutableBytes] : NULL, capacity, &length);
    if (status != POLYCALL_OK) {
        if (error != NULL) {
            NSString *detail = [OBNPolycall lastErrorDetail];
            *error = OBNMakeError(status, [OBNPolycall nameForStatus:status], detail, nil,
                                  status == POLYCALL_E_TOO_LARGE
                                      ? [NSNumber numberWithUnsignedLongLong:(unsigned long long)length]
                                      : nil);
        }
        return nil;
    }
    [payload setLength:length];
    message = [[OBNPolycallMessage alloc] initWithSender:OBNString(sender)
                                               messageID:OBNString(messageID)
                                                 payload:payload];
    return OBN_AUTORELEASE(message);
}

- (BOOL)cancel:(NSError **)error {
    return OBNCheck(polycall_peer_cancel(_handle), error);
}

- (NSString *)healthJSON:(NSError **)error {
    return OBNFetchText(_handle, polycall_peer_health, error);
}

@end
