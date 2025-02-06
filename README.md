A mummy router that captures parts of the url 


[The documentation for matching syntax (for now)](https://github.com/enthus1ast/nimUrlMatcher/blob/2ca5a8286b35280a1c1ba127a09de8d719d9499f/src/urlMatcher.nim#L48)


```Nim
import mummy
import matchingMummyRouter
var router: MatchRouter

proc getOneRecordHandler(request: Request, mt: MatchTable) =
  var headers: HttpHeaders
  headers["Content-Type"] = "text/plain"
  echo "MATCH RECORD: ", mt["id"]
  request.respond(200, headers, $mt["id"])

proc dumpHandler(request: Request, mt: MatchTable) =
  var headers: HttpHeaders
  headers["Content-Type"] = "text/plain"
  request.respond(200, headers, $mt)

proc getHandlerForVhost(request: Request, mt: MatchTable) =
  var headers: HttpHeaders
  headers["Content-Type"] = "text/plain"
  request.respond(200, headers, "vhost myhost.de")


router.get("myhost.de", "/", getHandlerForVhost)

router.post("/api/v1/record/@id:int", getOneRecordHandler)
router.get("/api/v1/recordGET/@id:int", getOneRecordHandler)

# Shows all different datatypes, matches on:
# /yes/-1337/23/21.42/foo
router.get("/@mybool:bool/@myint:int/@myabsint:absint/@myfloat:float/@mystring:string", dumpHandler)

# Serve all static files from the static folder:
router.get("/static/**", staticFileHandler)

let server = newServer(router)
server.serve(Port(9090))

```

Changelog:

    - 0.5.0 Vhost matching; all http verb procs (get, post, etc)
        got a `vhost` attribute, those handlers must be defined BEFORE the generic handlers TODO
