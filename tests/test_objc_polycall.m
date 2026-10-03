/*
 * objc-polycall test suite against the REAL installed Polycall core.
 *
 * Run from the repository root (`make test-objc`). Needs libpolycall and, for
 * the daemon and C-peer interop checks, the `polycall` CLI ($POLYCALL_CLI or
 * PATH); without the CLI those checks are reported as SKIP, never as PASS.
 * Prints one PASS/FAIL/SKIP line per check and exits non-zero on any FAIL.
 */
#import <Foundation/Foundation.h>

#import "OBNPolycall.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#if defined(__has_feature)
#  if __has_feature(objc_arc)
#    define T_ARC 1
#  endif
#endif
#ifndef T_ARC
#  define T_ARC 0
#endif
#if T_ARC
#  define T_RELEASE(x) ((void)0)
#  define T_POOL_BEGIN @autoreleasepool {
#  define T_POOL_END }
#else
#  define T_RELEASE(x) [(x) release]
#  define T_POOL_BEGIN { NSAutoreleasePool *t_pool_ = [[NSAutoreleasePool alloc] init];
#  define T_POOL_END [t_pool_ drain]; }
#endif

static int g_pass, g_fail, g_skip;
static NSString *g_token;
static NSString *g_cli;
static NSString *g_tmp;

#define S(x) ([[(x) description] UTF8String])
/* `cond` is evaluated exactly once (it often sends or receives). */
#define CHECK(cond, ...) do {                                              \
        BOOL check_ok_ = (cond) ? YES : NO;                                \
        if (check_ok_) { g_pass++; printf("PASS  "); }                     \
        else { g_fail++; printf("FAIL  "); }                               \
        printf(__VA_ARGS__);                                               \
        if (!check_ok_) printf("  [%s:%d]", __FILE__, __LINE__);           \
        printf("\n"); fflush(stdout);                                      \
    } while (0)
#define SKIP(...) do { g_skip++; printf("SKIP  "); printf(__VA_ARGS__); printf("\n"); fflush(stdout); } while (0)

/* An NSError that is exactly the binding's report of status `want`. */
static BOOL isStatus(NSError *error, int want) {
    return error != nil && [[error domain] isEqualToString:OBNPolycallErrorDomain]
        && [error code] == want
        && [[[error userInfo] objectForKey:OBNPolycallStatusNameKey]
               isEqualToString:[OBNPolycall nameForStatus:want]]
        && [[error userInfo] objectForKey:OBNPolycallDetailKey] != nil;
}

#define EXPECT_STATUS(ok, error, want, label) \
    CHECK(!(ok) && isStatus((error), (want)), "%s -> %s (got: %s)", (label), \
          S([OBNPolycall nameForStatus:(want)]), S((error)))

static NSDictionary *jsonObject(NSString *text) {
    id o;
    if (text == nil) return nil;
    o = [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding]
                                        options:0 error:NULL];
    return [o isKindOfClass:[NSDictionary class]] ? o : nil;
}

static NSString *writeFile(NSString *name, NSString *text) {
    NSString *path = [g_tmp stringByAppendingPathComponent:name];
    [[text dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:NO];
    return path;
}

static NSData *bytesOf(const char *s) {
    return [NSData dataWithBytes:s length:strlen(s)];
}

/* ---- the polycall CLI ---- */

static NSString *findCLI(void) {
    NSDictionary *env = [[NSProcessInfo processInfo] environment];
    NSString *explicit = [env objectForKey:@"POLYCALL_CLI"];
    NSEnumerator *dirs;
    NSString *dir;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (explicit != nil && [fm isExecutableFileAtPath:explicit]) return explicit;
    dirs = [[[env objectForKey:@"PATH"] componentsSeparatedByString:@":"] objectEnumerator];
    while ((dir = [dirs nextObject]) != nil) {
        NSString *candidate = [dir stringByAppendingPathComponent:@"polycall"];
        if ([dir length] > 0 && [fm isExecutableFileAtPath:candidate]) return candidate;
    }
    return nil;
}

static NSDictionary *cliEnvironment(NSString *token) {
    NSMutableDictionary *env = [NSMutableDictionary dictionaryWithDictionary:
                                   [[NSProcessInfo processInfo] environment]];
    [env setObject:token forKey:@"POLYCALL_DEV_TOKEN"];
    [env setObject:@"off" forKey:@"POLYCALL_TELEMETRY"];
    return env;
}

/* Run the CLI to completion; returns its exit status, stdout in *out. */
static int runCLI(NSArray *args, NSString *token, NSString **out) {
    NSTask *task = [[NSTask alloc] init];
    NSPipe *pipe = [NSPipe pipe];
    NSData *data;
    int status;
    [task setLaunchPath:g_cli];
    [task setArguments:args];
    [task setEnvironment:cliEnvironment(token != nil ? token : g_token)];
    [task setStandardOutput:pipe];
    [task setStandardError:pipe];
    [task launch];
    data = [[pipe fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];
    status = [task terminationStatus];
    T_RELEASE(task);
    if (out != NULL) {
        NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        *out = [NSString stringWithString:s != nil ? s : @""];
        T_RELEASE(s);
    }
    return status;
}

static NSString *waitForFile(NSString *path) {
    int i;
    for (i = 0; i < 200; ++i) {
        NSString *s = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
        s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([s length] > 0) return s;
        usleep(50000);
    }
    return nil;
}

/* ---- threads ---- */

@interface ReceiveWorker : NSObject
{
@public
    OBNPolycallPeer *peer;
    NSConditionLock *done;   /* 0 = running, 1 = finished */
    NSInteger code;          /* 0 = message, else the NSError code */
    NSString *messageID;
}
@end

@implementation ReceiveWorker
#if !T_ARC
- (void)dealloc { [done release]; [messageID release]; [super dealloc]; }
#endif
- (void)run:(id)unused {
    T_POOL_BEGIN
    NSError *error = nil;
    OBNPolycallMessage *m;
    (void)unused;
    m = [peer receiveWithTimeoutMs:OBNPolycallWaitForever error:&error];
    code = m != nil ? 0 : [error code];
    if (m != nil) messageID = [[m messageID] copy];
    [done lock];
    [done unlockWithCondition:1];
    T_POOL_END
}
@end

static ReceiveWorker *startReceive(OBNPolycallPeer *peer) {
    ReceiveWorker *w = [[ReceiveWorker alloc] init];
    w->peer = peer;
    w->done = [[NSConditionLock alloc] initWithCondition:0];
    w->code = 99;
    [NSThread detachNewThreadSelector:@selector(run:) toTarget:w withObject:nil];
    return w;  /* caller releases (MRC) */
}

static BOOL waitDone(ReceiveWorker *w, NSTimeInterval seconds) {
    if ([w->done lockWhenCondition:1 beforeDate:[NSDate dateWithTimeIntervalSinceNow:seconds]]) {
        [w->done unlock];
        return YES;
    }
    return NO;
}

@interface SendWorker : NSObject
{
@public
    OBNPolycallPeer *peer;
    NSString *target;
    int threadNo, count, failures;
    NSConditionLock *done;
}
@end

@implementation SendWorker
#if !T_ARC
- (void)dealloc { [done release]; [super dealloc]; }
#endif
- (void)run:(id)unused {
    T_POOL_BEGIN
    int i;
    (void)unused;
    for (i = 0; i < count; ++i) {
        NSError *error = nil;
        NSString *mid = [NSString stringWithFormat:@"t%d-m%d", threadNo, i];
        NSString *text = [NSString stringWithFormat:@"payload %d/%d", threadNo, i];
        if (![peer sendString:text toPeer:target messageID:mid timeoutMs:5000 error:&error]) {
            failures++;
            printf("      send %s failed: %s\n", S(mid), S(error));
        }
    }
    [done lock];
    [done unlockWithCondition:1];
    T_POOL_END
}
@end

@interface CallWorker : NSObject
{
@public
    NSString *endpoint;
    int n;
    BOOL ok;
    NSConditionLock *done;
}
@end

@implementation CallWorker
#if !T_ARC
- (void)dealloc { [done release]; [super dealloc]; }
#endif
- (void)run:(id)unused {
    T_POOL_BEGIN
    NSError *error = nil;
    NSString *input = [NSString stringWithFormat:@"{\"n\":%d}", n];
    NSString *out = [OBNPolycall callEndpoint:endpoint service:@"debug" operation:@"echo"
                                    inputJSON:input timeoutMs:5000 error:&error];
    NSString *want = [NSString stringWithFormat:@"{\"echo\":{\"n\":%d}}", n];
    (void)unused;
    ok = [[out stringByReplacingOccurrencesOfString:@" " withString:@""] isEqualToString:want];
    [done lock];
    [done unlockWithCondition:1];
    T_POOL_END
}
@end

/* ===================================================================== */

static void testLibrary(void) {
    NSError *error = nil;
    NSString *path;
    int s;
    BOOL allNamed = YES;
    printf("\n### library / ABI\n");
    CHECK([OBNPolycall abiVersion] == 1, "polycall_ffi_abi_version() == 1");
    CHECK([OBNPolycall requiredABIVersion] == 1, "binding requires ABI 1");
    CHECK([OBNPolycall checkABIVersion:&error], "checkABIVersion: passes (%s)", S(error));
    CHECK([[OBNPolycall libraryVersion] isEqualToString:@"1.1.0"], "library version %s", S([OBNPolycall libraryVersion]));
    path = [OBNPolycall libraryPath];
    CHECK(path != nil && [path rangeOfString:@"libpolycall"].location != NSNotFound, "library path %s", S(path));
    for (s = 0; s >= -18; --s) {
        if (![[OBNPolycall nameForStatus:s] hasPrefix:@"POLYCALL_"]) allNamed = NO;
    }
    CHECK(allNamed, "polycall_strerror names every status 0..-18");
    CHECK([[OBNPolycall nameForStatus:-999] rangeOfString:@"UNKNOWN"].location != NSNotFound, "unknown status -> UNKNOWN");
    error = nil;
    CHECK(![OBNPolycall runConfigAtPath:@"/nonexistent-dir/objc-polycallrc" error:&error]
          && isStatus(error, OBNPolycallStatusNotFound)
          && [[[error userInfo] objectForKey:OBNPolycallDetailKey] length] > 0
          && [[[error userInfo] objectForKey:@"configPath"] isEqualToString:@"/nonexistent-dir/objc-polycallrc"],
          "NSError carries status, name, detail and configPath (%s)", S(error));
    CHECK([[error localizedDescription] rangeOfString:@"POLYCALL_E_NOT_FOUND"].location != NSNotFound,
          "localizedDescription names the status: %s", S([error localizedDescription]));
    CHECK([[OBNPolycall lastErrorDetail] length] > 0, "lastErrorDetail after a failure: %s", S([OBNPolycall lastErrorDetail]));
    {
        unichar chars[] = { 'a', 0, 'b' };
        NSString *withNul = [NSString stringWithCharacters:chars length:3];
        error = nil;
        CHECK(![OBNPolycall runConfigAtPath:withNul error:&error] && [error code] == OBNPolycallStatusInvalidArgument
              && [[[error userInfo] objectForKey:OBNPolycallDetailKey] rangeOfString:@"NUL"].location != NSNotFound,
              "a string with U+0000 is refused, not truncated (%s)", S(error));
    }
}

static void testConfig(void) {
    NSError *error = nil;
    NSString *p;
    BOOL ok;
    printf("\n### configuration (polycall_ffi_run_config / describe)\n");
    CHECK([OBNPolycall rawStatusForConfigAtPath:@"objc-polycallrc"] == 0, "documented entry point: objc-polycallrc -> 0");
    CHECK([OBNPolycall runConfigAtPath:@"objc-polycallrc" error:&error], "objc-polycallrc strict (%s)", S(error));
    CHECK([OBNPolycall runConfigAtPath:@"examples/objc-polycallrc" strict:YES error:&error], "examples/objc-polycallrc strict (%s)", S(error));
    CHECK([OBNPolycall runConfigAtPath:@"objc-polycallrc" strict:NO error:&error], "objc-polycallrc lenient");
    p = [g_tmp stringByAppendingPathComponent:@"missing-polycallrc"];
    CHECK([OBNPolycall rawStatusForConfigAtPath:p] == OBNPolycallStatusNotFound, "missing file raw status -7");
    error = nil; ok = [OBNPolycall runConfigAtPath:p error:&error];
    EXPECT_STATUS(ok, error, OBNPolycallStatusNotFound, "missing file");
    error = nil; ok = [OBNPolycall runConfigAtPath:@"" error:&error];
    EXPECT_STATUS(ok, error, OBNPolycallStatusInvalidArgument, "empty path");
    {
        BOOL threw = NO;
        @try { [OBNPolycall rawStatusForConfigAtPath:(NSString *)nil]; }
        @catch (NSException *e) { threw = [[e name] isEqualToString:NSInvalidArgumentException]; }
        CHECK(threw, "rawStatusForConfigAtPath:nil raises NSInvalidArgumentException (documented)");
    }
    p = writeFile(@"bad-polycallrc", @"max_connections=lots\n");
    error = nil; ok = [OBNPolycall runConfigAtPath:p strict:NO error:&error];
    EXPECT_STATUS(ok, error, OBNPolycallStatusConfig, "invalid value");
    CHECK([[[error userInfo] objectForKey:OBNPolycallDetailKey] rangeOfString:@"max_connections"].location != NSNotFound,
          "detail names the key: %s", S([[error userInfo] objectForKey:OBNPolycallDetailKey]));
    p = writeFile(@"unknown-polycallrc", @"log_level=info\nmystery_key=1\n");
    CHECK([OBNPolycall runConfigAtPath:p strict:NO error:NULL], "unknown key lenient -> OK (warning)");
    error = nil; ok = [OBNPolycall runConfigAtPath:p strict:YES error:&error];
    EXPECT_STATUS(ok, error, OBNPolycallStatusConfig, "unknown key strict");
    CHECK([OBNPolycall rawStatusForConfigAtPath:p] == OBNPolycallStatusConfig, "documented entry point is strict");
    p = writeFile(@"tls-polycallrc", @"tls_enabled=true\ncert_file=/x/c.pem\nkey_file=/x/k.pem\n");
    CHECK([OBNPolycall runConfigAtPath:p strict:NO error:NULL], "tls_enabled=true lenient -> OK");
    error = nil; ok = [OBNPolycall runConfigAtPath:p strict:YES error:&error];
    EXPECT_STATUS(ok, error, OBNPolycallStatusUnsupported, "tls_enabled=true strict");
    {
        unichar name[] = { 0xDC, 'n', 'i', 'c', 0xF8, 'd', 0xE9, '-', 0x65E5, 0x672C, '-', 'p', 'o', 'l', 'y',
                           'c', 'a', 'l', 'l', 'r', 'c' };
        NSString *n = [NSString stringWithCharacters:name length:sizeof name / sizeof name[0]];
        NSString *json;
        p = writeFile(n, @"log_level=info\nmax_connections=10\n");
        error = nil;
        CHECK([OBNPolycall runConfigAtPath:p error:&error], "non-ASCII path %s (%s)", S(p), S(error));
        json = [OBNPolycall describeConfigAtPath:p error:&error];
        CHECK([json rangeOfString:@"max_connections"].location != NSNotFound, "describe opens the non-ASCII path");
    }
    p = writeFile(@"Polycallfile", @"server node 8080:8084\nnetwork start\nworkspace_root=/opt/x\n"
                                   @"log_directory=/var/log/x\ndaemon_endpoint=127.0.0.1:0\n"
                                   @"auth_token_env=POLYCALL_DEV_TOKEN\npeer_node_id=alpha\npeer beta 127.0.0.1:9002\n");
    {
        NSString *json;
        error = nil;
        CHECK([OBNPolycall runConfigAtPath:p error:&error], "Polycallfile strict (%s)", S(error));
        json = [OBNPolycall describeConfigAtPath:p error:&error];
        CHECK(jsonObject(json) != nil && [json rangeOfString:@"\"beta\":\"127.0.0.1:9002\""].location != NSNotFound,
              "describe JSON lists the peer: %.80s", S(json));
        error = nil;
        CHECK([OBNPolycall describeConfigAtPath:[g_tmp stringByAppendingPathComponent:@"nope"] error:&error] == nil
              && isStatus(error, OBNPolycallStatusNotFound), "describe missing file -> NOT_FOUND");
    }
}

static void testCall(void) {
    NSString *stateDir, *pcfile, *out = nil, *ep, *state;
    NSError *error = nil;
    NSDictionary *json;
    int rc, i;
    printf("\n### polycall_call against a polycall daemon\n");
    if (g_cli == nil) {
        SKIP("call checks: polycall CLI not found (set POLYCALL_CLI or PATH)");
        return;
    }
    stateDir = [g_tmp stringByAppendingPathComponent:@"daemon-state"];
    /* the daemon requires a project file named exactly "Polycallfile" */
    [[NSFileManager defaultManager] createDirectoryAtPath:[g_tmp stringByAppendingPathComponent:@"daemon"]
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    pcfile = writeFile(@"daemon/Polycallfile", @"log_level=info\n");
    rc = runCLI([NSArray arrayWithObjects:@"daemon", @"start", @"--endpoint", @"127.0.0.1:0",
                 @"--state-dir", stateDir, pcfile, nil], nil, &out);
    state = [NSString stringWithContentsOfFile:[stateDir stringByAppendingPathComponent:@"daemon.json"]
                                      encoding:NSUTF8StringEncoding error:NULL];
    ep = [jsonObject(state) objectForKey:@"endpoint"];
    CHECK(rc == 0 && ep != nil, "daemon started at %s (%s)", S(ep), S(out));
    if (ep == nil) return;

    out = [OBNPolycall callEndpoint:ep service:@"debug" operation:@"echo"
                          inputJSON:@"{\"a\":1,\"s\":\"h\\u00e9llo\"}" timeoutMs:5000 error:&error];
    json = [jsonObject(out) objectForKey:@"echo"];
    CHECK([[json objectForKey:@"a"] intValue] == 1 && [[json objectForKey:@"s"] isEqualToString:@"héllo"],
          "debug.echo round trip: %s", S(out));
    out = [OBNPolycall callEndpoint:ep service:@"debug" operation:@"echo" inputJSON:nil timeoutMs:5000 error:&error];
    CHECK([[out stringByReplacingOccurrencesOfString:@" " withString:@""] isEqualToString:@"{\"echo\":null}"],
          "nil input is sent as null: %s", S(out));
    out = [OBNPolycall callEndpoint:ep service:@"inventory" operation:@"get"
                          inputJSON:@"{\"item_id\":\"widget-a\"}" timeoutMs:5000 error:&error];
    CHECK([[jsonObject(out) objectForKey:@"quantity"] intValue] == 42, "inventory.get widget-a -> 42: %s", S(out));
    error = nil;
    out = [OBNPolycall callEndpoint:ep service:@"debug" operation:@"nope" inputJSON:nil timeoutMs:5000 error:&error];
    EXPECT_STATUS(out != nil, error, OBNPolycallStatusNotFound, "unknown operation");
    CHECK([[[error userInfo] objectForKey:OBNPolycallRemoteErrorKey] rangeOfString:@"operation.unknown"].location != NSNotFound,
          "remote error object: %s", S([[error userInfo] objectForKey:OBNPolycallRemoteErrorKey]));
    error = nil;
    out = [OBNPolycall callEndpoint:ep service:@"inventory" operation:@"get" inputJSON:@"{\"item_id\":\"nope\"}"
                          timeoutMs:5000 error:&error];
    CHECK(out == nil && ([error code] == OBNPolycallStatusRemote || [error code] == OBNPolycallStatusNotFound)
          && [[[error userInfo] objectForKey:OBNPolycallRemoteErrorKey] rangeOfString:@"item.unknown"].location != NSNotFound,
          "operation error carries item.unknown (%s)", S(error));
    error = nil;
    {
        NSDate *start = [NSDate date];
        out = [OBNPolycall callEndpoint:ep service:@"debug" operation:@"sleep" inputJSON:@"{\"ms\":3000}"
                              timeoutMs:300 error:&error];
        EXPECT_STATUS(out != nil, error, OBNPolycallStatusTimeout, "deadline exceeded (300 ms vs 3000 ms sleep)");
        CHECK(-[start timeIntervalSinceNow] < 2.5, "deadline honoured in %.2fs", -[start timeIntervalSinceNow]);
    }
    error = nil;
    out = [OBNPolycall callEndpoint:ep service:@"debug" operation:@"echo" inputJSON:@"{not json" timeoutMs:5000 error:&error];
    EXPECT_STATUS(out != nil, error, OBNPolycallStatusInvalidArgument, "invalid input JSON");
    error = nil;
    out = [OBNPolycall callEndpoint:@"127.0.0.1:1" service:@"debug" operation:@"echo" inputJSON:nil timeoutMs:2000 error:&error];
    EXPECT_STATUS(out != nil, error, OBNPolycallStatusTransport, "no runtime at the endpoint");
    error = nil;
    out = [OBNPolycall callEndpoint:ep service:@"debug" operation:@"echo" inputJSON:nil timeoutMs:0 error:&error];
    EXPECT_STATUS(out != nil, error, OBNPolycallStatusInvalidArgument, "timeout 0");
    error = nil;
    out = [OBNPolycall callEndpoint:ep service:@"debug" operation:@"echo" inputJSON:nil timeoutMs:600001 error:&error];
    EXPECT_STATUS(out != nil, error, OBNPolycallStatusInvalidArgument, "timeout 600001");
    error = nil;
    out = [OBNPolycall callEndpoint:ep service:@"debug" operation:@"echo" inputJSON:nil timeoutMs:1 error:&error];
    CHECK(out != nil || [error code] == OBNPolycallStatusTimeout,
          "timeout 1 is in range (succeeds or times out, never INVALID_ARGUMENT): %s", S(out != nil ? (id)out : (id)error));
    CHECK([OBNPolycall callEndpoint:ep service:@"debug" operation:@"echo" inputJSON:nil timeoutMs:600000 error:&error] != nil,
          "timeout 600000 accepted (%s)", S(error));
    error = nil;
    out = [OBNPolycall callEndpoint:ep service:@"debug" operation:@"echo" inputJSON:@"{\"k\":\"0123456789\"}"
                          timeoutMs:5000 outputCapacity:4 error:&error];
    EXPECT_STATUS(out != nil, error, OBNPolycallStatusTooLarge, "4-byte output buffer");
    {
        NSUInteger need = [[[error userInfo] objectForKey:OBNPolycallRequiredSizeKey] unsignedIntegerValue];
        out = [OBNPolycall callEndpoint:ep service:@"debug" operation:@"echo" inputJSON:@"{\"k\":\"0123456789\"}"
                              timeoutMs:5000 outputCapacity:need + 1 error:&error];
        CHECK(need > 4 && [[out dataUsingEncoding:NSUTF8StringEncoding] length] == need,
              "required size %lu is exact", (unsigned long)need);
    }
    {
        CallWorker *workers[16];
        BOOL allOK = YES;
        for (i = 0; i < 16; ++i) {
            workers[i] = [[CallWorker alloc] init];
            workers[i]->endpoint = ep;
            workers[i]->n = i;
            workers[i]->done = [[NSConditionLock alloc] initWithCondition:0];
            [NSThread detachNewThreadSelector:@selector(run:) toTarget:workers[i] withObject:nil];
        }
        for (i = 0; i < 16; ++i) {
            if (![workers[i]->done lockWhenCondition:1 beforeDate:[NSDate dateWithTimeIntervalSinceNow:20]]) allOK = NO;
            else [workers[i]->done unlock];
            if (!workers[i]->ok) allOK = NO;
        }
        for (i = 0; i < 16; ++i) T_RELEASE(workers[i]);
        CHECK(allOK, "16 concurrent calls from 16 threads all correct");
    }
    rc = runCLI([NSArray arrayWithObjects:@"daemon", @"stop", @"--state-dir", stateDir, pcfile, nil], nil, &out);
    CHECK(rc == 0, "daemon stopped (%s)", S(out));
}

static OBNPolycallPeer *openPeer(NSString *nodeID, NSString *bind, NSString *token) {
    NSError *error = nil;
    OBNPolycallPeer *p = [OBNPolycallPeer peerWithNodeID:nodeID bindEndpoint:bind authToken:token error:&error];
    if (p == nil) printf("      open %s failed: %s\n", S(nodeID), S(error));
    return p;
}

static BOOL expectMessage(OBNPolycallPeer *peer, NSString *from, NSString *mid, NSData *payload) {
    NSError *error = nil;
    OBNPolycallMessage *m = [peer receiveWithTimeoutMs:5000 error:&error];
    BOOL ok = m != nil && [[m sender] isEqualToString:from] && [[m messageID] isEqualToString:mid]
        && [[m payload] isEqualToData:payload];
    if (!ok) printf("      got %s / %s (want %s %s, %lu bytes)\n", S(m), S(error), S(from), S(mid),
                    (unsigned long)[payload length]);
    return ok;
}

static void testPeers(void) {
    OBNPolycallPeer *alpha, *beta, *p;
    NSString *epA, *epB, *s;
    NSError *error = nil;
    BOOL ok;
    int i;
    printf("\n### peer nodes\n");
    error = nil; p = [OBNPolycallPeer peerWithNodeID:@"" bindEndpoint:@"127.0.0.1:0" authToken:nil error:&error];
    EXPECT_STATUS(p != nil, error, OBNPolycallStatusInvalidArgument, "open with empty id");
    error = nil; p = [OBNPolycallPeer peerWithNodeID:@"bad id" bindEndpoint:@"127.0.0.1:0" authToken:nil error:&error];
    EXPECT_STATUS(p != nil, error, OBNPolycallStatusInvalidArgument, "open with space in id");
    error = nil;
    p = [OBNPolycallPeer peerWithNodeID:[@"" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0]
                           bindEndpoint:nil authToken:nil error:&error];
    EXPECT_STATUS(p != nil, error, OBNPolycallStatusInvalidArgument, "open with 64-byte id");
    p = [OBNPolycallPeer peerWithNodeID:[@"" stringByPaddingToLength:63 withString:@"a" startingAtIndex:0]
                           bindEndpoint:nil authToken:nil error:&error];
    CHECK(p != nil && [p close:NULL], "63-byte id accepted");
    error = nil; p = [OBNPolycallPeer peerWithNodeID:@"x" bindEndpoint:@"nohostport" authToken:nil error:&error];
    EXPECT_STATUS(p != nil, error, OBNPolycallStatusInvalidArgument, "open with bad endpoint");
    error = nil; p = [OBNPolycallPeer peerWithNodeID:@"x" bindEndpoint:@"0.0.0.0:0" authToken:nil error:&error];
    EXPECT_STATUS(p != nil, error, OBNPolycallStatusConfig, "non-loopback bind without a token");

    alpha = openPeer(@"alpha", @"127.0.0.1:0", g_token);
    beta = openPeer(@"beta", @"127.0.0.1:0", g_token);
    CHECK(alpha != nil && beta != nil, "open alpha and beta (shared token)");
    if (alpha == nil || beta == nil) return;
    epA = [alpha endpoint:NULL];
    epB = [beta endpoint:NULL];
    CHECK([epA hasPrefix:@"127.0.0.1:"] && [[epA substringFromIndex:10] intValue] > 0, "alpha bound to %s", S(epA));
    CHECK([alpha handle] > 0 && [alpha handle] != [beta handle], "handles positive and distinct (%d, %d)",
          (int)[alpha handle], (int)[beta handle]);
    CHECK([[beta nodeID:NULL] isEqualToString:@"beta"], "node id is beta");
    error = nil; p = [OBNPolycallPeer peerWithNodeID:@"dup" bindEndpoint:epA authToken:nil error:&error];
    EXPECT_STATUS(p != nil, error, OBNPolycallStatusAddressInUse, "second node on alpha's port");

    /* registry ownership */
    CHECK([alpha registerPeer:@"beta" endpoint:epB error:NULL], "alpha registers beta");
    CHECK([[alpha registry:NULL] isEqualToDictionary:[NSDictionary dictionaryWithObject:epB forKey:@"beta"]],
          "alpha's registry: %s", S([alpha registryJSON:NULL]));
    CHECK([[beta registry:NULL] count] == 0, "beta's registry still empty (no implicit sync)");
    error = nil; ok = [alpha registerPeer:@"bad id" endpoint:epB error:&error];
    EXPECT_STATUS(ok, error, OBNPolycallStatusInvalidArgument, "register invalid id");
    error = nil; ok = [alpha registerPeer:@"x" endpoint:@"127.0.0.1:0" error:&error];
    EXPECT_STATUS(ok, error, OBNPolycallStatusInvalidArgument, "register port 0");
    error = nil; ok = [alpha unregisterPeer:@"nobody" error:&error];
    EXPECT_STATUS(ok, error, OBNPolycallStatusNotFound, "unregister unknown");
    CHECK([beta registerPeer:@"alpha" endpoint:epA error:NULL], "beta registers alpha");

    /* ping / health */
    CHECK([alpha ping:@"beta" timeoutMs:2000 error:NULL], "ping beta by id");
    CHECK([alpha ping:epB timeoutMs:2000 error:NULL], "ping beta by endpoint");
    [alpha registerPeer:@"impostor" endpoint:epB error:NULL];
    error = nil; ok = [alpha ping:@"impostor" timeoutMs:2000 error:&error];
    EXPECT_STATUS(ok, error, OBNPolycallStatusProtocol, "identity mismatch on ping");
    [alpha unregisterPeer:@"impostor" error:NULL];
    error = nil; ok = [alpha ping:@"nobody" timeoutMs:500 error:&error];
    EXPECT_STATUS(ok, error, OBNPolycallStatusNotFound, "ping unknown id");
    error = nil; ok = [alpha ping:@"127.0.0.1:1" timeoutMs:1000 error:&error];
    EXPECT_STATUS(ok, error, OBNPolycallStatusTransport, "ping closed port");
    s = [beta healthJSON:NULL];
    CHECK([[jsonObject(s) objectForKey:@"node_id"] isEqualToString:@"beta"]
          && [[jsonObject(s) objectForKey:@"status"] isEqualToString:@"ok"], "health JSON: %.90s", S(s));

    /* payloads both directions */
    CHECK([alpha sendString:@"hello beta" toPeer:@"beta" messageID:@"a2b-1" timeoutMs:2000 error:NULL]
          && expectMessage(beta, @"alpha", @"a2b-1", bytesOf("hello beta")), "alpha -> beta, verified at beta");
    CHECK([beta sendString:@"hello alpha" toPeer:@"alpha" messageID:@"b2a-1" timeoutMs:2000 error:NULL]
          && expectMessage(alpha, @"beta", @"b2a-1", bytesOf("hello alpha")), "beta -> alpha, verified at alpha");
    CHECK([alpha sendData:[NSData data] toPeer:@"beta" messageID:@"empty-1" timeoutMs:2000 error:NULL]
          && expectMessage(beta, @"alpha", @"empty-1", [NSData data]), "empty payload");
    {
        const char *u = "h\xc3\xa9llo \xe2\x80\x94 \xe4\xb8\x96\xe7\x95\x8c \xf0\x9f\x8c\x8d";
        OBNPolycallMessage *m;
        [alpha sendData:bytesOf(u) toPeer:@"beta" messageID:@"utf8-1" timeoutMs:2000 error:NULL];
        m = [beta receiveWithTimeoutMs:3000 error:NULL];
        CHECK([[m payload] isEqualToData:bytesOf(u)] && [[m text] isEqualToString:[NSString stringWithUTF8String:u]],
              "UTF-8 payload byte-identical");
    }
    {
        unsigned char bin[260];
        NSData *d;
        for (i = 0; i < 256; ++i) bin[i] = (unsigned char)i;
        bin[256] = 0; bin[257] = 0; bin[258] = 255; bin[259] = 0;
        d = [NSData dataWithBytes:bin length:sizeof bin];
        CHECK([alpha sendData:d toPeer:@"beta" messageID:@"bin-1" timeoutMs:2000 error:NULL]
              && expectMessage(beta, @"alpha", @"bin-1", d), "binary payload with embedded NULs");
    }
    {
        NSMutableData *max = [NSMutableData dataWithLength:OBNPolycallMaxPayload];
        unsigned char *b = [max mutableBytes];
        NSUInteger k;
        for (k = 0; k < OBNPolycallMaxPayload; ++k) b[k] = (unsigned char)(k * 31 + 7);
        CHECK([alpha sendData:max toPeer:@"beta" messageID:@"max-1" timeoutMs:15000 error:&error]
              && expectMessage(beta, @"alpha", @"max-1", max), "exactly 1 MiB delivered intact (%s)", S(error));
        [max appendBytes:"x" length:1];
        error = nil; ok = [alpha sendData:max toPeer:@"beta" messageID:@"over-1" timeoutMs:2000 error:&error];
        EXPECT_STATUS(ok, error, OBNPolycallStatusTooLarge, "1 MiB + 1 refused before sending");
    }
    {
        OBNPolycallMessage *m;
        [alpha sendString:@"0123456789" toPeer:@"beta" messageID:@"size-1" timeoutMs:2000 error:NULL];
        error = nil; m = [beta receiveWithTimeoutMs:2000 capacity:4 error:&error];
        EXPECT_STATUS(m != nil, error, OBNPolycallStatusTooLarge, "receive into a 4-byte buffer");
        CHECK([[[error userInfo] objectForKey:OBNPolycallRequiredSizeKey] intValue] == 10, "required size 10 reported");
        CHECK(expectMessage(beta, @"alpha", @"size-1", bytesOf("0123456789")), "message stayed queued after TOO_LARGE");
    }
    {
        NSDate *start = [NSDate date];
        OBNPolycallMessage *m;
        error = nil; m = [beta receiveWithTimeoutMs:150 error:&error];
        EXPECT_STATUS(m != nil, error, OBNPolycallStatusTimeout, "empty inbox: receive(150 ms)");
        CHECK(-[start timeIntervalSinceNow] >= 0.1 && -[start timeIntervalSinceNow] < 3, "timeout after %.3fs",
              -[start timeIntervalSinceNow]);
        error = nil; m = [beta receiveWithTimeoutMs:0 error:&error];
        EXPECT_STATUS(m != nil, error, OBNPolycallStatusTimeout, "receive(0) polls");
    }
    CHECK([alpha sendString:@"once" toPeer:@"beta" messageID:@"dup-1" timeoutMs:2000 error:NULL]
          && [alpha sendString:@"once" toPeer:@"beta" messageID:@"dup-1" timeoutMs:2000 error:NULL]
          && expectMessage(beta, @"alpha", @"dup-1", bytesOf("once"))
          && [beta receiveWithTimeoutMs:300 error:NULL] == nil, "duplicate message id delivered once");
    error = nil; ok = [alpha sendString:@"x" toPeer:@"beta" messageID:@"bad id!" timeoutMs:2000 error:&error];
    EXPECT_STATUS(ok, error, OBNPolycallStatusInvalidArgument, "invalid message id");
    {
        OBNPolycallMessage *m;
        [alpha sendString:@"auto" toPeer:@"beta" messageID:nil timeoutMs:2000 error:NULL];
        m = [beta receiveWithTimeoutMs:2000 error:NULL];
        CHECK([[m messageID] length] > 0 && [[m text] isEqualToString:@"auto"], "core generates a message id (%s)", S([m messageID]));
    }

    /* failures are reported */
    {
        OBNPolycallPeer *doomed = openPeer(@"doomed", @"127.0.0.1:0", g_token);
        NSString *ep = [doomed endpoint:NULL];
        [doomed close:NULL];
        error = nil; ok = [alpha sendString:@"void" toPeer:ep messageID:nil timeoutMs:2000 error:&error];
        EXPECT_STATUS(ok, error, OBNPolycallStatusTransport, "send to a dead peer");
    }
    error = nil; ok = [alpha sendString:@"x" toPeer:@"unknown-peer" messageID:nil timeoutMs:1000 error:&error];
    EXPECT_STATUS(ok, error, OBNPolycallStatusNotFound, "send to an unregistered id");
    {
        OBNPolycallPeer *carol = openPeer(@"carol", nil, nil);
        OBNPolycallPeer *mallory = openPeer(@"mallory", nil, @"not-the-token");
        error = nil; ok = [carol sendString:@"x" toPeer:epB messageID:nil timeoutMs:2000 error:&error];
        EXPECT_STATUS(ok, error, OBNPolycallStatusAuth, "no token -> AUTH");
        error = nil; ok = [mallory sendString:@"x" toPeer:epB messageID:nil timeoutMs:2000 error:&error];
        EXPECT_STATUS(ok, error, OBNPolycallStatusAuth, "wrong token -> AUTH");
        CHECK([beta receiveWithTimeoutMs:200 error:NULL] == nil, "rejected messages are not queued");
        CHECK([[carol endpoint:NULL] isEqualToString:@""], "send-only node has an empty endpoint");
        [carol close:NULL];
        [mallory close:NULL];
    }

    /* backpressure */
    {
        int accepted = 0;
        NSInteger last = 0;
        for (i = 0; i < 300; ++i) {
            error = nil;
            if ([alpha sendString:@"f" toPeer:@"beta" messageID:[NSString stringWithFormat:@"flood-%d", i]
                        timeoutMs:2000 error:&error]) accepted++;
            else { last = [error code]; break; }
        }
        CHECK(accepted == 256 && last == OBNPolycallStatusBusy, "inbox accepts 256 then BUSY (accepted %d, then %ld)",
              accepted, (long)last);
        for (i = 0; i < accepted; ++i) [beta receiveWithTimeoutMs:2000 error:NULL];
        CHECK([alpha sendString:@"after" toPeer:@"beta" messageID:@"after-drain" timeoutMs:2000 error:NULL]
              && expectMessage(beta, @"alpha", @"after-drain", bytesOf("after")), "accepts again after draining");
    }

    /* cancel / close wake a blocked receive */
    {
        ReceiveWorker *w = startReceive(beta);
        usleep(300000);
        CHECK(!waitDone(w, 0.05), "receive is blocked");
        CHECK([beta cancel:NULL], "cancel");
        CHECK(waitDone(w, 3) && w->code == OBNPolycallStatusCancelled, "cancel woke the blocked receive (code %ld)", (long)w->code);
        error = nil;
        CHECK([beta receiveWithTimeoutMs:100 error:&error] == nil && [error code] == OBNPolycallStatusTimeout,
              "later receives wait normally");
        T_RELEASE(w);
        w = startReceive(alpha);
        usleep(200000);
        [beta sendString:@"wake" toPeer:@"alpha" messageID:@"wake-1" timeoutMs:2000 error:NULL];
        CHECK(waitDone(w, 5) && w->code == 0 && [w->messageID isEqualToString:@"wake-1"], "blocked receive gets a message from another thread");
        T_RELEASE(w);
    }

    /* concurrency */
    {
        SendWorker *workers[8];
        NSMutableDictionary *seen = [NSMutableDictionary dictionary];
        int failures = 0, t;
        for (t = 0; t < 8; ++t) {
            workers[t] = [[SendWorker alloc] init];
            workers[t]->peer = alpha; workers[t]->target = @"beta";
            workers[t]->threadNo = t; workers[t]->count = 30;
            workers[t]->done = [[NSConditionLock alloc] initWithCondition:0];
            [NSThread detachNewThreadSelector:@selector(run:) toTarget:workers[t] withObject:nil];
        }
        for (t = 0; t < 8; ++t) {
            if ([workers[t]->done lockWhenCondition:1 beforeDate:[NSDate dateWithTimeIntervalSinceNow:60]]) [workers[t]->done unlock];
            else failures++;
            failures += workers[t]->failures;
        }
        for (t = 0; t < 8; ++t) T_RELEASE(workers[t]);
        for (i = 0; i < 240; ++i) {
            OBNPolycallMessage *m = [beta receiveWithTimeoutMs:5000 error:NULL];
            if (m == nil) break;
            [seen setObject:[m text] forKey:[m messageID]];
        }
        ok = failures == 0 && [seen count] == 240;
        for (t = 0; t < 8 && ok; ++t) {
            for (i = 0; i < 30 && ok; ++i) {
                ok = [[seen objectForKey:[NSString stringWithFormat:@"t%d-m%d", t, i]]
                         isEqualToString:[NSString stringWithFormat:@"payload %d/%d", t, i]];
            }
        }
        CHECK(ok, "8 threads x 30 concurrent sends all delivered exactly (failures %d, received %lu)",
              failures, (unsigned long)[seen count]);
    }

    /* close: wakes a blocked receive; double close and use after close */
    {
        ReceiveWorker *w = startReceive(beta);
        usleep(300000);
        CHECK([beta close:&error], "close beta");
        CHECK(waitDone(w, 3) && w->code == OBNPolycallStatusClosed, "close woke the blocked receive (code %ld)", (long)w->code);
        T_RELEASE(w);
    }
    CHECK([beta isClosed], "isClosed after close:");
    error = nil; ok = [beta close:&error];
    EXPECT_STATUS(ok, error, OBNPolycallStatusInvalidHandle, "double close");
    error = nil;
    CHECK([beta endpoint:&error] == nil && isStatus(error, OBNPolycallStatusInvalidHandle), "endpoint after close");
    error = nil; ok = [beta sendString:@"x" toPeer:epA messageID:nil timeoutMs:1000 error:&error];
    EXPECT_STATUS(ok, error, OBNPolycallStatusInvalidHandle, "send after close");
    error = nil;
    CHECK([beta receiveWithTimeoutMs:0 error:&error] == nil && isStatus(error, OBNPolycallStatusInvalidHandle), "receive after close");
    error = nil; ok = [beta cancel:&error];
    EXPECT_STATUS(ok, error, OBNPolycallStatusInvalidHandle, "cancel after close");
    error = nil;
    CHECK([beta healthJSON:&error] == nil && isStatus(error, OBNPolycallStatusInvalidHandle), "health after close");
    CHECK([alpha close:&error], "close alpha");
}

static void testInterop(void) {
    NSString *epFile, *cEP, *swEP, *out = nil, *payloadFile;
    NSTask *serve;
    OBNPolycallPeer *node;
    NSError *error = nil;
    NSDictionary *json;
    NSData *toC, *toObjC, *decoded;
    OBNPolycallMessage *m;
    int rc, i;
    printf("\n### interop with the C CLI (polycall peer serve / send / recv)\n");
    if (g_cli == nil) {
        SKIP("interop checks: polycall CLI not found (set POLYCALL_CLI or PATH)");
        return;
    }
    epFile = [g_tmp stringByAppendingPathComponent:@"cnode.ep"];
    serve = [[NSTask alloc] init];
    [serve setLaunchPath:g_cli];
    [serve setArguments:[NSArray arrayWithObjects:@"peer", @"serve", @"--node-id", @"cnode",
                         @"--endpoint", @"127.0.0.1:0", @"--endpoint-file", epFile, nil]];
    [serve setEnvironment:cliEnvironment(g_token)];
    [serve setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
    [serve setStandardError:[NSFileHandle fileHandleWithNullDevice]];
    [serve launch];
    cEP = waitForFile(epFile);
    CHECK(cEP != nil, "C node (polycall peer serve, pid %d) listening at %s", [serve processIdentifier], S(cEP));
    node = openPeer(@"objcnode", @"127.0.0.1:0", g_token);
    swEP = [node endpoint:NULL];
    if (cEP != nil && node != nil) {
        CHECK([node registerPeer:@"cnode" endpoint:cEP error:NULL] && [node ping:@"cnode" timeoutMs:2000 error:&error],
              "ObjC node pings the C node under its id (%s)", S(error));
        {
            const char raw[] = "h\xc3\xa9llo from objc \xf0\x9f\x8c\x8d\0\x01\x02\0\xff";
            toC = [NSData dataWithBytes:raw length:sizeof raw - 1];
        }
        CHECK([node sendData:toC toPeer:@"cnode" messageID:@"o2c-1" timeoutMs:3000 error:&error], "ObjC -> C sent (%s)", S(error));
        rc = runCLI([NSArray arrayWithObjects:@"peer", @"recv", @"--to", cEP, @"-t", @"3000", nil], nil, &out);
        json = jsonObject(out);
        decoded = [[NSData alloc] initWithBase64EncodedString:[json objectForKey:@"payload_b64"] options:0];
        CHECK(rc == 0 && [[json objectForKey:@"from"] isEqualToString:@"objcnode"]
              && [[json objectForKey:@"id"] isEqualToString:@"o2c-1"] && [decoded isEqualToData:toC],
              "C side received exact bytes, sender objcnode, id o2c-1 (%s)", S(out));
        T_RELEASE(decoded);
        {
            unsigned char bin[300];
            for (i = 0; i < 300; ++i) bin[i] = (unsigned char)(i % 256);
            toObjC = [NSData dataWithBytes:bin length:sizeof bin];
        }
        payloadFile = [g_tmp stringByAppendingPathComponent:@"c2o.bin"];
        [toObjC writeToFile:payloadFile atomically:NO];
        rc = runCLI([NSArray arrayWithObjects:@"peer", @"send", @"--from", @"cnode", @"--to", swEP,
                     @"--id", @"c2o-1", @"--payload-file", payloadFile, nil], nil, &out);
        m = [node receiveWithTimeoutMs:3000 error:&error];
        CHECK(rc == 0 && [[m sender] isEqualToString:@"cnode"] && [[m messageID] isEqualToString:@"c2o-1"]
              && [[m payload] isEqualToData:toObjC], "C -> ObjC binary payload exact (%s)", S(m));
        rc = runCLI([NSArray arrayWithObjects:@"peer", @"send", @"--from", @"cnode", @"--to", swEP,
                     @"--id", @"c2o-2", @"--payload", @"世界 from C", nil], nil, &out);
        m = [node receiveWithTimeoutMs:3000 error:&error];
        CHECK(rc == 0 && [[m text] isEqualToString:@"世界 from C"] && [[m messageID] isEqualToString:@"c2o-2"],
              "C -> ObjC UTF-8 text (%s)", S([m text]));
        rc = runCLI([NSArray arrayWithObjects:@"peer", @"send", @"--from", @"mallory", @"--to", swEP,
                     @"--payload", @"x", nil], @"wrong-token", &out);
        CHECK(rc == 7 && [node receiveWithTimeoutMs:200 error:NULL] == nil, "CLI sender with a wrong token rejected (exit %d)", rc);
        {
            NSMutableArray *tasks = [NSMutableArray array];
            NSMutableDictionary *got = [NSMutableDictionary dictionary];
            BOOL allOK = YES;
            for (i = 0; i < 12; ++i) {
                NSTask *t = [[NSTask alloc] init];
                [t setLaunchPath:g_cli];
                [t setArguments:[NSArray arrayWithObjects:@"peer", @"send", @"--from",
                                 [NSString stringWithFormat:@"csender%d", i], @"--to", swEP, @"--id",
                                 [NSString stringWithFormat:@"cc-%d", i], @"--payload",
                                 [NSString stringWithFormat:@"n%d", i], nil]];
                [t setEnvironment:cliEnvironment(g_token)];
                [t setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
                [t launch];
                [tasks addObject:t];
                T_RELEASE(t);
            }
            for (i = 0; i < 12; ++i) {
                [[tasks objectAtIndex:i] waitUntilExit];
                if ([[tasks objectAtIndex:i] terminationStatus] != 0) allOK = NO;
            }
            for (i = 0; i < 12; ++i) {
                m = [node receiveWithTimeoutMs:5000 error:NULL];
                if (m != nil) [got setObject:[NSString stringWithFormat:@"%@:%@", [m sender], [m text]] forKey:[m messageID]];
            }
            for (i = 0; i < 12; ++i) {
                if (![[got objectForKey:[NSString stringWithFormat:@"cc-%d", i]]
                         isEqualToString:[NSString stringWithFormat:@"csender%d:n%d", i, i]]) allOK = NO;
            }
            CHECK(allOK, "12 concurrent CLI sender processes -> ObjC node, all exact");
        }
    }
    [node close:NULL];
    [serve terminate];
    [serve waitUntilExit];
    T_RELEASE(serve);
}

int main(int argc, const char *argv[]) {
    T_POOL_BEGIN
    (void)argc; (void)argv;
    g_token = [[NSString alloc] initWithFormat:@"objc-qa-%@",
                  [[NSProcessInfo processInfo] globallyUniqueString]];
    g_cli = findCLI();
    g_tmp = [[NSTemporaryDirectory() stringByAppendingPathComponent:
                 [NSString stringWithFormat:@"objc-polycall-%@", [[NSProcessInfo processInfo] globallyUniqueString]]] copy];
    [[NSFileManager defaultManager] createDirectoryAtPath:g_tmp withIntermediateDirectories:YES
                                               attributes:nil error:NULL];
    printf("objc-polycall real-core tests: libpolycall %s (ABI %d) from %s; CLI %s\n",
           S([OBNPolycall libraryVersion]), [OBNPolycall abiVersion], S([OBNPolycall libraryPath]),
           g_cli != nil ? S(g_cli) : "(not found)");
    testLibrary();
    testConfig();
    testCall();
    testPeers();
    testInterop();
    [[NSFileManager defaultManager] removeItemAtPath:g_tmp error:NULL];
    T_RELEASE(g_token);
    T_RELEASE(g_tmp);
    printf("\n--- objc-polycall: %d passed, %d failed, %d skipped ---\n", g_pass, g_fail, g_skip);
    T_POOL_END
    return g_fail == 0 ? 0 : 1;
}
