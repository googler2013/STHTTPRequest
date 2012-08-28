//
//  STHTTPRequest.m
//  STHTTPRequest
//
//  Created by Nicolas Seriot on 07.11.11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "STHTTPRequest.h"

static NSMutableDictionary *sharedCredentialsStorage;

@interface STHTTPRequest ()
@property (nonatomic) NSInteger responseStatus;
@property (nonatomic, retain) NSMutableData *responseData;
@property (nonatomic, retain) NSString *responseStringEncodingName;
@property (nonatomic, retain) NSDictionary *responseHeaders;
@property (nonatomic, retain) NSURL *url;
@property (nonatomic, retain) NSError *error;
@end

@interface NSData (Base64)
- (NSString *)base64Encoding; // private API
@end

@implementation STHTTPRequest

@synthesize credential=_credential;

#pragma mark Initializers

+ (STHTTPRequest *)requestWithURL:(NSURL *)url {
    if(url == nil) return nil;
    return [[[self alloc] initWithURL:url] autorelease];
}

+ (STHTTPRequest *)requestWithURLString:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString];
    return [self requestWithURL:url];
}

- (STHTTPRequest *)initWithURL:(NSURL *)theURL {
    
    if (self = [super init]) {
        _url = [theURL retain];
        _responseData = [[NSMutableData alloc] init];
        _requestHeaders = [[NSMutableDictionary dictionary] retain];
        _postDataEncoding = NSUTF8StringEncoding;
    }
    
    return self;
}

+ (void)clearSession {
    [self deleteAllCookies];
    [self deleteAllCredentials];
}

- (void)dealloc {
    [_responseStringEncodingName release];
    [_requestHeaders release];
    [_url release];
    [_responseData release];
    [_responseHeaders release];
    [_responseString release];
    [_completionBlock release];
    [_errorBlock release];
    [_credential release];
    [_proxyCredential release];
    [_POSTDictionary release];
    [_error release];
    [super dealloc];
}

#pragma mark Credentials

+ (NSMutableDictionary *)sharedCredentialsStorage {
    if(sharedCredentialsStorage == nil) {
        sharedCredentialsStorage = [[NSMutableDictionary dictionary] retain];
    }
    return sharedCredentialsStorage;
}

+ (NSURLCredential *)sessionAuthenticationCredentialsForURL:(NSURL *)requestURL {
    return [[[self class] sharedCredentialsStorage] valueForKey:[requestURL host]];
}

+ (void)deleteAllCredentials {
    [sharedCredentialsStorage autorelease];
    sharedCredentialsStorage = [[NSMutableDictionary dictionary] retain];
}

- (void)setCredential:(NSURLCredential *)c {
#if DEBUG
    NSAssert(_url, @"missing url to set credential");
#endif
    [[[self class] sharedCredentialsStorage] setObject:c forKey:[_url host]];
}

- (NSURLCredential *)credential {
    return [[[self class] sharedCredentialsStorage] valueForKey:[_url host]];
}

- (void)setUsername:(NSString *)username password:(NSString *)password {
    NSURLCredential *c = [NSURLCredential credentialWithUser:username
                                                    password:password
                                                 persistence:NSURLCredentialPersistenceNone];
    
    [self setCredential:c];
}

- (void)setProxyUsername:(NSString *)username password:(NSString *)password {
    NSURLCredential *c = [NSURLCredential credentialWithUser:username
                                                    password:password
                                                 persistence:NSURLCredentialPersistenceNone];
    
    [self setProxyCredential:c];
}

- (NSString *)username {
    return [[self credential] user];
}

- (NSString *)password {
    return [[self credential] password];
}

#pragma mark Cookies

+ (NSArray *)sessionCookies {
    NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    return [cookieStorage cookies];
}

+ (void)deleteSessionCookies {
    for(NSHTTPCookie *cookie in [self sessionCookies]) {
        [[NSHTTPCookieStorage sharedHTTPCookieStorage] deleteCookie:cookie];
    }
}

+ (void)deleteAllCookies {
    NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    NSArray *cookies = [cookieStorage cookies];
    for (NSHTTPCookie *cookie in cookies) {
        [cookieStorage deleteCookie:cookie];
    }
}

+ (void)addCookie:(NSHTTPCookie *)cookie forURL:(NSURL *)url {
    NSArray *cookies = [NSArray arrayWithObject:cookie];
	
    [[NSHTTPCookieStorage sharedHTTPCookieStorage] setCookies:cookies forURL:url mainDocumentURL:nil];
}

+ (void)addCookieWithName:(NSString *)name value:(NSString *)value url:(NSURL *)url {
    
    NSMutableDictionary *cookieProperties = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                             name, NSHTTPCookieName,
                                             value, NSHTTPCookieValue,
                                             [url host], NSHTTPCookieDomain,
                                             [url host], NSHTTPCookieOriginURL,
                                             @"FALSE", NSHTTPCookieDiscard,
                                             @"/", NSHTTPCookiePath,
                                             @"0", NSHTTPCookieVersion,
                                             [[NSDate date] dateByAddingTimeInterval:3600 * 24 * 30], NSHTTPCookieExpires,
                                             nil];
    
    NSHTTPCookie *cookie = [NSHTTPCookie cookieWithProperties:cookieProperties];
    
    [[self class] addCookie:cookie forURL:url];
}

- (NSArray *)requestCookies {
    return [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL:[_url absoluteURL]];
}

- (void)addCookie:(NSHTTPCookie *)cookie {
    [[self class] addCookie:cookie forURL:_url];
}

- (void)addCookieWithName:(NSString *)name value:(NSString *)value {
    [[self class] addCookieWithName:name value:value url:_url];
}

#pragma mark Headers

- (void)setHeaderWithName:(NSString *)name value:(NSString *)value {
    if(name == nil || value == nil) return;
    [[self requestHeaders] setObject:value forKey:name];
}

- (void)removeHeaderWithName:(NSString *)name {
    if(name == nil) return;
    [[self requestHeaders] removeObjectForKey:name];
}

- (NSURL *)urlWithCredentials {
    
    NSURLCredential *credentialForHost = [self credential];
    
    if(credentialForHost == nil) return _url; // no credentials to add
    
    NSString *scheme = [_url scheme];
    NSString *host = [_url host];
    
    BOOL hostAlreadyContainsCredentials = [host rangeOfString:@"@"].location != NSNotFound;
    if(hostAlreadyContainsCredentials) return _url;
    
    NSMutableString *resourceSpecifier = [[[_url resourceSpecifier] mutableCopy] autorelease];
    
    if([resourceSpecifier hasPrefix:@"//"] == NO) return nil;
    
    NSString *userPassword = [NSString stringWithFormat:@"%@:%@@", credentialForHost.user, credentialForHost.password];
    
    [resourceSpecifier insertString:userPassword atIndex:2];
    
    NSString *urlString = [NSString stringWithFormat:@"%@:%@", scheme, resourceSpecifier];
    
    return [NSURL URLWithString:urlString];
}

- (NSURLRequest *)requestByAddingCredentialsToURL:(BOOL)credentialsInRequest sendBasicAuthenticationHeaders:(BOOL)sendBasicAuthenticationHeaders {
    
    NSURL *theURL = credentialsInRequest ? [self urlWithCredentials] : _url;
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:theURL];
    
    if([_POSTDictionary count] > 0) {
        
        NSMutableArray *ma = [NSMutableArray arrayWithCapacity:[_POSTDictionary count]];
        
        for(NSString *k in _POSTDictionary) {
            NSString *kv = [NSString stringWithFormat:@"%@=%@", k, [_POSTDictionary objectForKey:k]];
            [ma addObject:kv];
        }
        
        NSString *s = [ma componentsJoinedByString:@"&"];
        NSData *data = [s dataUsingEncoding:_postDataEncoding allowLossyConversion:YES];
        
        [request setHTTPMethod:@"POST"];
        [request setHTTPBody:data];
    }
    
    [_requestHeaders enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        [request addValue:obj forHTTPHeaderField:key];
    }];
        
    NSURLCredential *credentialForHost = [self credential];
            
    if(sendBasicAuthenticationHeaders && credentialsInRequest && credentialForHost) {
        NSString *authString = [NSString stringWithFormat:@"%@:%@", credentialForHost.user, credentialForHost.password];
        NSData *authData = [authString dataUsingEncoding:NSASCIIStringEncoding];
        NSString *authValue = [NSString stringWithFormat:@"Basic %@", [authData base64Encoding]];
        [request addValue:authValue forHTTPHeaderField:@"Authorization"];
    }
    
    return request;
}

- (NSURLRequest *)request {
    return [self requestByAddingCredentialsToURL:NO sendBasicAuthenticationHeaders:YES];
}

- (NSURLRequest *)requestByAddingCredentialsToURL {
    return [self requestByAddingCredentialsToURL:YES sendBasicAuthenticationHeaders:YES];
}

#pragma mark Response

+ (NSString *)stringWithData:(NSData *)data encodingName:(NSString *)encodingName {
    if(data == nil) return nil;
    
    NSStringEncoding encoding = NSUTF8StringEncoding;
    
    if(encodingName != nil) {
        
        encoding = CFStringConvertEncodingToNSStringEncoding(CFStringConvertIANACharSetNameToEncoding((CFStringRef)encodingName));
        
        if(encoding == kCFStringEncodingInvalidId) {
            encoding = NSUTF8StringEncoding; // by default
        }
    }
    
    return [[[NSString alloc] initWithData:data encoding:encoding] autorelease];
}

- (void)logRequest:(NSURLRequest *)request {
    
    NSLog(@"--------------------------------------");
    
    NSLog(@"%@", [request URL]);
    
    NSArray *cookies = [self requestCookies];
    
    if([cookies count]) NSLog(@"COOKIES");
    
    for(NSHTTPCookie *cookie in cookies) {
        NSLog(@"\t %@ = %@", [cookie name], [cookie value]);
    }
    
    NSDictionary *d = [self POSTDictionary];
    
    if([d count]) NSLog(@"POST DATA");
    
    [d enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        NSLog(@"\t %@ = %@", key, obj);
    }];
    
    NSLog(@"--------------------------------------");
}

#pragma mark Start Request

- (void)startAsynchronous {
    NSURLRequest *request = [self requestByAddingCredentialsToURL];
    
#if DEBUG
    [self logRequest:request];
#endif
    
    // NSURLConnection *connection = [NSURLConnection connectionWithRequest:request delegate:self];
    // http://www.pixeldock.com/blog/how-to-avoid-blocked-downloads-during-scrolling/
    NSURLConnection *connection = [[[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:NO] autorelease];
    [connection scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    [connection start];
    
    if(connection == nil) {
        NSString *s = @"can't create connection";
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:s forKey:NSLocalizedDescriptionKey];
        self.error = [NSError errorWithDomain:NSStringFromClass([self class]) code:0 userInfo:userInfo];
        _errorBlock(_error);
    }
}

- (NSString *)startSynchronousWithError:(NSError **)e {
    
    self.responseHeaders = nil;
    self.responseStatus = 0;
    
    NSURLRequest *request = [self requestByAddingCredentialsToURL];
    
    NSURLResponse *urlResponse = nil;
    
    NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&urlResponse error:e];
    if(data == nil) return nil;
    
    self.responseData = [NSMutableData dataWithData:data];
    
    if([urlResponse isKindOfClass:[NSHTTPURLResponse class]]) {
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)urlResponse;
        
        self.responseHeaders = [httpResponse allHeaderFields];
        self.responseStatus = [httpResponse statusCode];
        self.responseStringEncodingName = [httpResponse textEncodingName];
    }
    
    return [[self class] stringWithData:_responseData encodingName:_responseStringEncodingName];
}

#pragma mark NSURLConnectionDelegate

- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    
    if ([challenge previousFailureCount] <= 2) {
        
        NSURLCredential *currentCredential = nil;
        
        if ([[challenge protectionSpace] isProxy] && _proxyCredential != nil) {
            currentCredential = _proxyCredential;
        } else {
            currentCredential = [self credential];
        }
        
        if (currentCredential) {
            [[challenge sender] useCredential:currentCredential forAuthenticationChallenge:challenge];
            return;
        }
    }
    
    [connection cancel];
    
    [[challenge sender] cancelAuthenticationChallenge:challenge];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    
    if([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse *r = (NSHTTPURLResponse *)response;
        self.responseHeaders = [r allHeaderFields];
        self.responseStatus = [r statusCode];
        self.responseStringEncodingName = [r textEncodingName];
    }
    
    [_responseData setLength:0];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)theData {
    [_responseData appendData:theData];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    self.responseString = [[self class] stringWithData:_responseData encodingName:_responseStringEncodingName];
    
    _completionBlock(_responseHeaders, [self responseString]);
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)e {
    self.error = e;
    _errorBlock(_error);
}

@end

/**/

@implementation NSError (STHTTPRequest)

- (BOOL)st_isAuthenticationError {
    if([[self domain] isEqualToString:NSURLErrorDomain] == NO) return NO;
    
    return ([self code] == kCFURLErrorUserCancelledAuthentication || [self code] == kCFURLErrorUserAuthenticationRequired);
}

@end

/**/

#if DEBUG
@implementation NSURLRequest (IgnoreSSLValidation)

+ (BOOL)allowsAnyHTTPSCertificateForHost:(NSString *)host {
    return NO;
}
@end
#endif