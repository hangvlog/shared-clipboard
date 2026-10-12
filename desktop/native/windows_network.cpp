#include <windows.h>
#include <winhttp.h>
#include <wincrypt.h>
#include <shlobj.h>
#include <string>
#include <vector>
#include <thread>
#include <mutex>
#include <fstream>
#include <atomic>
#include "bridge.h"
static std::mutex socketMutex;
static HINTERNET socketHandle=nullptr;
static std::atomic<unsigned long long> currentGeneration{0};
static std::wstring wide(const char *s){int n=MultiByteToWideChar(CP_UTF8,0,s,-1,nullptr,0);std::wstring v(n,L'\0');MultiByteToWideChar(CP_UTF8,0,s,-1,v.data(),n);v.pop_back();return v;}
static char *copy(const std::string &s){auto *p=(char*)malloc(s.size()+1);memcpy(p,s.c_str(),s.size()+1);return p;}
extern "C" void native_free(void *p){free(p);}
struct Request {
 HINTERNET session=nullptr,connection=nullptr,request=nullptr;
 ~Request(){if(request)WinHttpCloseHandle(request);if(connection)WinHttpCloseHandle(connection);if(session)WinHttpCloseHandle(session);}
 bool open(const char *method,const char *url,bool websocket){
  std::wstring target=wide(url);if(target.rfind(L"wss:",0)==0)target.replace(0,3,L"https");else if(target.rfind(L"ws:",0)==0)target.replace(0,2,L"http");
  URL_COMPONENTS parts={sizeof(parts)};parts.dwHostNameLength=parts.dwUrlPathLength=parts.dwExtraInfoLength=(DWORD)-1;
  if(!WinHttpCrackUrl(target.c_str(),0,0,&parts))return false;
  std::wstring host(parts.lpszHostName,parts.dwHostNameLength),path(parts.lpszUrlPath,parts.dwUrlPathLength);
  if(parts.dwExtraInfoLength)path.append(parts.lpszExtraInfo,parts.dwExtraInfoLength);
  session=WinHttpOpen(L"SharedClipboard/1.1",WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,WINHTTP_NO_PROXY_NAME,WINHTTP_NO_PROXY_BYPASS,0);if(!session)return false;
  WinHttpSetTimeouts(session,10000,10000,15000,websocket?60000:15000);
  connection=WinHttpConnect(session,host.c_str(),parts.nPort,0);if(!connection)return false;
  request=WinHttpOpenRequest(connection,wide(method).c_str(),path.c_str(),nullptr,WINHTTP_NO_REFERER,WINHTTP_DEFAULT_ACCEPT_TYPES,parts.nScheme==INTERNET_SCHEME_HTTPS?WINHTTP_FLAG_SECURE:0);
  if(!request)return false;
  if(websocket&&!WinHttpSetOption(request,WINHTTP_OPTION_UPGRADE_TO_WEB_SOCKET,nullptr,0))return false;
  return true;
 }
};
extern "C" char *native_request(const char *method,const char *url,const char *token,const char *body,int *status){
 *status=0;Request req;if(!req.open(method,url,false))return copy("");
 std::wstring headers=L"Content-Type: application/json\r\n";if(*token)headers+=L"Authorization: Bearer "+wide(token)+L"\r\n";
 DWORD size=(DWORD)strlen(body);if(!WinHttpSendRequest(req.request,headers.c_str(),(DWORD)-1,(void*)body,size,size,0)||!WinHttpReceiveResponse(req.request,nullptr))return copy("");
 DWORD code=0,len=sizeof(code);WinHttpQueryHeaders(req.request,WINHTTP_QUERY_STATUS_CODE|WINHTTP_QUERY_FLAG_NUMBER,WINHTTP_HEADER_NAME_BY_INDEX,&code,&len,WINHTTP_NO_HEADER_INDEX);
 std::string output;char buffer[16384];DWORD read=0;
 while(WinHttpReadData(req.request,buffer,sizeof(buffer),&read)&&read){if(output.size()+read>12*1024*1024)return copy("");output.append(buffer,read);}
 *status=(int)code;return copy(output);
}
// Escape protocol text into a JSON envelope without inspecting clipboard contents.
static std::string escaped(const std::string &s){std::string out="\"";for(unsigned char c:s){if(c=='"'||c=='\\'){out+='\\';out+=c;}else if(c<32){char b[7];sprintf_s(b,"\\u%04x",c);out+=b;}else out+=c;}return out+'"';}
extern "C" void native_ws_close(){++currentGeneration;std::lock_guard<std::mutex> lock(socketMutex);if(socketHandle){WinHttpWebSocketShutdown(socketHandle,WINHTTP_WEB_SOCKET_SUCCESS_CLOSE_STATUS,nullptr,0);socketHandle=nullptr;}}
extern "C" void native_ws_open(const char *url,unsigned long long generation){
 currentGeneration=generation;std::string target=url;
 std::thread([target,generation]{
  Request req;HINTERNET socket=nullptr;
  if(req.open("GET",target.c_str(),true)&&WinHttpSendRequest(req.request,WINHTTP_NO_ADDITIONAL_HEADERS,0,WINHTTP_NO_REQUEST_DATA,0,0,0)&&WinHttpReceiveResponse(req.request,nullptr))socket=WinHttpWebSocketCompleteUpgrade(req.request,0);
  if(!socket){fprintf(stderr,"WebSocket upgrade failed: %lu\n",GetLastError());}
  if(socket){
   WinHttpCloseHandle(req.request);req.request=nullptr;
   {std::lock_guard<std::mutex> lock(socketMutex);if(currentGeneration!=generation){WinHttpCloseHandle(socket);return;}socketHandle=socket;}
   char buffer[16384];std::string packet;DWORD read;WINHTTP_WEB_SOCKET_BUFFER_TYPE type;
   while(currentGeneration==generation&&WinHttpWebSocketReceive(socket,buffer,sizeof(buffer),&read,&type)==NO_ERROR){
    if(type==WINHTTP_WEB_SOCKET_CLOSE_BUFFER_TYPE)break;
    if(packet.size()+read>6*1024*1024)break;packet.append(buffer,read);
    if(type==WINHTTP_WEB_SOCKET_UTF8_MESSAGE_BUFFER_TYPE){std::string event="{\"generation\":"+std::to_string(generation)+",\"text\":"+escaped(packet)+"}";sc_event(3,event.c_str());packet.clear();}
   }
   {std::lock_guard<std::mutex> lock(socketMutex);if(socketHandle==socket)socketHandle=nullptr;}
   WinHttpCloseHandle(socket);
  }
  std::string id=std::to_string(generation);sc_event(4,id.c_str());
 }).detach();
}
extern "C" void native_ws_send(const char *text){std::lock_guard<std::mutex> lock(socketMutex);if(socketHandle)WinHttpWebSocketSend(socketHandle,WINHTTP_WEB_SOCKET_UTF8_MESSAGE_BUFFER_TYPE,(void*)text,(DWORD)strlen(text));}
static std::wstring secretPath(){PWSTR dir=nullptr;if(FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData,0,nullptr,&dir)))return L"";std::wstring path=dir;CoTaskMemFree(dir);path+=L"\\SharedClipboard";CreateDirectoryW(path.c_str(),nullptr);return path+L"\\session.dat";}
extern "C" char *native_secret_load(){
 auto path=secretPath();std::ifstream file(path,std::ios::binary);std::vector<char> bytes((std::istreambuf_iterator<char>(file)),{});
 if(bytes.empty()||bytes.size()>16*1024*1024)return copy("");DATA_BLOB input={(DWORD)bytes.size(),(BYTE*)bytes.data()},output={};
 if(!CryptUnprotectData(&input,nullptr,nullptr,nullptr,nullptr,CRYPTPROTECT_UI_FORBIDDEN,&output))return copy("");
 std::string plain((char*)output.pbData,output.cbData);SecureZeroMemory(output.pbData,output.cbData);LocalFree(output.pbData);return copy(plain);
}
extern "C" int native_secret_save(const char *text){
 DATA_BLOB input={(DWORD)strlen(text),(BYTE*)text},output={};if(!CryptProtectData(&input,L"Shared Clipboard",nullptr,nullptr,nullptr,CRYPTPROTECT_UI_FORBIDDEN,&output))return 0;
 auto path=secretPath(),tmp=path+L".tmp";std::ofstream file(tmp,std::ios::binary|std::ios::trunc);file.write((char*)output.pbData,output.cbData);file.close();LocalFree(output.pbData);
 return file.good()&&MoveFileExW(tmp.c_str(),path.c_str(),MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH);
}

extern "C" char *native_data_dir(){auto path=secretPath();if(path.empty())return copy("");path.resize(path.find_last_of(L'\\'));int n=WideCharToMultiByte(CP_UTF8,0,path.c_str(),(int)path.size(),nullptr,0,nullptr,nullptr);std::string v(n,'\0');WideCharToMultiByte(CP_UTF8,0,path.c_str(),(int)path.size(),v.data(),n,nullptr,nullptr);return copy(v);}
