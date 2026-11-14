#ifndef HTTP_SHIM_H
#define HTTP_SHIM_H

/* 普通 C 适配层（stub）。接真 curl 时只替换这一组函数；
   当前不碰网络，只记录请求字段，send() 固定返回 200 + 一段 JSON。 */

struct HttpRequest {
    char *url;
    char *verb;
    char *accept;
    int timeout_ms;
    int headers;
};

struct HttpResponse {
    int status;
    char *body;
};

/* 工厂：构造只在这里发生，调用点看不到这些字段。 */
static inline struct HttpRequest http_request_new(const char *url, const char *verb)
{
    struct HttpRequest r;
    r.url = (char *)url;
    r.verb = (char *)verb;
    r.accept = "";
    r.timeout_ms = 0;
    r.headers = 0;
    return r;
}

static inline struct HttpRequest http_request_header(struct HttpRequest r,
                                                     const char *name,
                                                     const char *value)
{
    if (name != 0 && value != 0) {
        r.headers = r.headers + 1;
        if (name[0] == 'A' && name[1] == 'c') r.accept = (char *)value;
    }
    return r;
}

static inline struct HttpRequest http_request_timeout(struct HttpRequest r, int ms)
{
    r.timeout_ms = ms;
    return r;
}

/* 唯一会“发请求”的位置。stub；接 curl 时改成 curl_easy_perform。 */
static inline struct HttpResponse http_request_send(struct HttpRequest r)
{
    struct HttpResponse resp;
    if (r.timeout_ms < 0) {
        resp.status = 408;
        resp.body = "stub: timeout";
    } else {
        resp.status = 200;
        resp.body = "{\"users\":3}";
    }
    return resp;
}

static inline int http_response_status(struct HttpResponse r) { return r.status; }
static inline char *http_response_body(struct HttpResponse r) { return r.body; }

#endif
