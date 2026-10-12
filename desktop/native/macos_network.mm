#import <Foundation/Foundation.h>
#import <Security/Security.h>
#include "bridge.h"
#include <stdlib.h>
#include <string.h>
static NSURLSessionWebSocketTask *socketTask;
static unsigned long long currentGeneration;
static dispatch_queue_t networkQueue;
static void initializeQueue(){static dispatch_once_t once;dispatch_once(&once,^{networkQueue=dispatch_queue_create("clipboard.network",DISPATCH_QUEUE_SERIAL);});}
static char *stringCopy(NSString *s){return strdup((s?:@"").UTF8String);}
extern "C" void native_free(void *p){free(p);}
extern "C" char *native_request(const char *method,const char *url,const char *token,const char *body,int *status){
 @autoreleasepool {
  NSURL *target=[NSURL URLWithString:@(url)];
  if(!target){*status=0;return nullptr;}
  NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:target];
  request.HTTPMethod=@(method);request.timeoutInterval=15;
  [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
  if(strlen(token)>0)[request setValue:[@"Bearer " stringByAppendingString:@(token)] forHTTPHeaderField:@"Authorization"];
  if(strlen(body)>0)request.HTTPBody=[@(body) dataUsingEncoding:NSUTF8StringEncoding];
  dispatch_semaphore_t ready=dispatch_semaphore_create(0);
  __block NSData *result;__block NSInteger code=0;
  NSURLSessionConfiguration *config=[NSURLSessionConfiguration ephemeralSessionConfiguration];
  config.timeoutIntervalForRequest=15;config.timeoutIntervalForResource=20;
  NSURLSession *session=[NSURLSession sessionWithConfiguration:config];
  [[session dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
    if(!error&&data.length<=12*1024*1024){result=data;code=((NSHTTPURLResponse*)response).statusCode;}
    dispatch_semaphore_signal(ready);
  }] resume];
  dispatch_semaphore_wait(ready,dispatch_time(DISPATCH_TIME_NOW,22*NSEC_PER_SEC));
  [session invalidateAndCancel];*status=(int)code;
  return stringCopy(result?[[NSString alloc]initWithData:result encoding:NSUTF8StringEncoding]:@"");
 }
}
static void receivePacket(NSURLSessionWebSocketTask *task,unsigned long long generation){
 [task receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *message,NSError *error){
  if(error){NSString *s=[NSString stringWithFormat:@"%llu",generation];sc_event(4,s.UTF8String);return;}
  if(message.string&&message.string.length<=6*1024*1024){
   NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"generation":@(generation),@"text":message.string} options:0 error:nil];
   NSString *text=[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];sc_event(3,text.UTF8String);
  }
  initializeQueue();dispatch_async(networkQueue,^{if(task==socketTask&&generation==currentGeneration)receivePacket(task,generation);});
 }];
}
extern "C" void native_ws_open(const char *url,unsigned long long generation){
 NSString *s=@(url);initializeQueue();dispatch_async(networkQueue,^{
  [socketTask cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure reason:nil];
  currentGeneration=generation;
  socketTask=[[NSURLSession sharedSession]webSocketTaskWithURL:[NSURL URLWithString:s]];
  socketTask.maximumMessageSize=6*1024*1024;
  [socketTask resume];receivePacket(socketTask,generation);
 });
}
extern "C" void native_ws_send(const char *text){NSString *s=@(text);initializeQueue();dispatch_async(networkQueue,^{
 [socketTask sendMessage:[[NSURLSessionWebSocketMessage alloc]initWithString:s] completionHandler:^(NSError *error){if(error){NSString *idString=[NSString stringWithFormat:@"%llu",currentGeneration];sc_event(4,idString.UTF8String);}}];
});}
extern "C" void native_ws_close(){initializeQueue();dispatch_async(networkQueue,^{[socketTask cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure reason:nil];socketTask=nil;});}
