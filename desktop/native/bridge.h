#pragma once
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
void sc_start(void);
void sc_event(int kind, const char *data);
void sc_login(const char *user, const char *password, const char *encryption);
void sc_history_select(int index);
void sc_release(char *text);
int native_run(void);
void native_session(int logged_in);
void native_status(const char *text);
void native_history_begin(void);
void native_history_item(const char *id, const char *text);
void native_history_end(void);
void native_detail(const char *id, const char *text, const unsigned char *image, size_t length, int success);
char *native_request(const char *method, const char *url, const char *token, const char *body, int *status);
void native_ws_open(const char *url, unsigned long long generation);
void native_ws_send(const char *text);
void native_ws_close(void);
char *native_secret_load(void);
int native_secret_save(const char *text);
char *native_clipboard_text(void);
unsigned char *native_clipboard_png(size_t *length);
int native_clipboard_write(const char *text, const unsigned char *image, size_t length);
void native_free(void *memory);
#ifdef __cplusplus
}
#endif
