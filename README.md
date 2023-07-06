A mummy router that captures parts of the url 


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


router.post("/api/v1/record/@id:int", getOneRecordHandler)
router.get("/api/v1/recordGET/@id:int", getOneRecordHandler)

# Shows all different datatypes, matches on:
# /yes/-1337/23/21.42/foo
router.get("/@mybool:bool/@myint:int/@myabsint:absint/@myfloat:float/@mystring:string", dumpHandler)

let server = newServer(router)
server.serve(Port(9090))

```


