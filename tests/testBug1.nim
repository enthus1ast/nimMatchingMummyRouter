# This is just an example to get you started. You may wish to put all of your
# tests into a single file, or separate them into multiple `test1`, `test2`
# etc. files (better names are recommended, just make sure the name starts with
# the letter 't').
#
# To run these tests, simply execute `nimble test`.

import unittest

import matchingMummyRouter
import mummyStaticFiles

# test "can add":
#   check add(5, 5) == 10

import mummy
import matchingMummyRouter
var router: MatchRouter

proc getOneRecordHandler(request: Request, mt: MatchTable) =
  var headers: HttpHeaders
  headers["Content-Type"] = "text/plain"
  echo "MATCH RECORD: ", mt["id"]
  request.respond(200, headers, $request & " " & $mt["id"])

proc dumpHandler(request: Request, mt: MatchTable) =
  var headers: HttpHeaders
  headers["Content-Type"] = "text/plain"
  request.respond(200, headers, $mt)


# router.get("/static/id:int/**", dumpHandler)
# router.get("/static/**", dumpHandler)
router.get("/static/**", staticFileHandler)

router.get("/api/v1/record/@id:int", getOneRecordHandler)
router.post("/api/v1/record/@id:int", getOneRecordHandler)
# echo router
# router.get("/api/v1/recordGET/@id:int", getOneRecordHandler)

# Shows all different datatypes, matches on:
# /yes/-1337/23/21.42/foo
# router.get("/@mybool:bool/@myint:int/@myabsint:absint/@myfloat:float/@mystring:string", dumpHandler)

let server = newServer(router)
server.serve(Port(9090))

  # var router: MatchRouter
  # router.get("/", indexHandler)
  # router.post("/", indexPostHandler)
