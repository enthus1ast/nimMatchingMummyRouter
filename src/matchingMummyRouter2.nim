import mummy
import strutils
import webby
import urlMatcher
import sequtils

proc unpackValue*(str: string, val: var string) = val = str
proc unpackValue*(str: string, val: var float)  = val = parseFloat(str)
proc unpackValue*(str: string, val: var bool)   = val = parseBool(str)
proc unpackValue*(str: string, val: var char)   = val = str[0]

proc unpackValue*[T: enum](str: string, val: var T) =
  val = parseEnum[T](str)

# Generic overload for integer subranges like Natural or Positive
proc unpackValue*[T: SomeInteger](str: string, val: var T) =
  try:
    val = parseInt(str).T
  except RangeDefect:
    raise newException(ValueError, "invalid " & $T)


type ParamPair* = tuple[key, val: string]

proc matchPath*(pattern, path: string, params: var seq[ParamPair]): bool =
  let patParts = pattern.split('/').filterIt(it.len > 0)
  let reqParts = path.split('/').filterIt(it.len > 0)

  if patParts.len != reqParts.len:
    return false

  params.setLen(0)
  for i in 0 ..< patParts.len:
    let pat = patParts[i]
    let req = reqParts[i]

    if pat.startsWith("@") or pat.startsWith(":"):
      # Strip prefix to get param name
      let paramName = pat[1 .. ^1]
      params.add((key: paramName, val: req))
    elif pat != req:
      return false

  return true


proc unpackNamedParams*[T: object](params: seq[ParamPair]): T =
  for fieldName, fieldValue in result.fieldPairs:
    var found = false
    for param in params:
      if param.key == fieldName:
        unpackValue(param.val, fieldValue)
        found = true
        break
    
    if not found:
      raise newException(ValueError, "Missing parameter for object field: '" & fieldName & "'")


proc defaultNotFound*(request: Request) =
  var headers: HttpHeaders
  headers["Content-Type"] = "text/plain"
  request.respond(404, headers, "not found")

proc defaultForbidden*(request: Request) =
  var headers: HttpHeaders
  headers["Content-Type"] = "text/plain"
  request.respond(403, headers, "forbidden")

proc defaultErrorHandler*(request: Request) =
  var headers: HttpHeaders
  headers["Content-Type"] = "text/plain"
  request.respond(405, headers, "method not allowed")

type
  TypedMatchRequestHandler*[T] = proc(request: Request, data: T) {.gcsafe.}

  Route* = object
    vhost: string
    httpMethod: string
    pattern: string
    handler: proc(request: Request, params: seq[ParamPair]) {.gcsafe.}

  TsRouter* = object
    routes: seq[Route]
    notFoundHandler*: RequestHandler = defaultNotFound
    methodNotAllowedHandler*: RequestHandler = defaultForbidden
    errorHandler*: RequestHandler = defaultErrorHandler

# Converts raw string pairs into typed T instance
proc wrapHandler*[T: object](handler: TypedMatchRequestHandler[T]): proc(request: Request, params: seq[ParamPair]) {.gcsafe.} =
  return proc(request: Request, params: seq[ParamPair]) {.gcsafe.} =
    try:
      let obj = unpackNamedParams[T](params)
      handler(request, obj)
    except CatchableError as e:
      var headers: HttpHeaders
      headers["Content-Type"] = "text/plain"
      when not defined(release):
        request.respond(400, headers, "400 Bad Request: " & e.msg)
      else:
        ## In production, to not send the error over the network, but log it
        request.respond(400, headers, "400 Bad Request")
        echo e.msg ## TODO where to put the logs

# =============================================================================
# Without VHost
# =============================================================================

proc get*[T: object](router: var TsRouter, pattern: string, handler: TypedMatchRequestHandler[T]) =
  router.routes.add Route(httpMethod: "GET", pattern: pattern, handler: wrapHandler[T](handler))

proc post*[T: object](router: var TsRouter, pattern: string, handler: TypedMatchRequestHandler[T]) =
  router.routes.add Route(httpMethod: "POST", pattern: pattern, handler: wrapHandler[T](handler))

proc put*[T: object](router: var TsRouter, pattern: string, handler: TypedMatchRequestHandler[T]) =
  router.routes.add Route(httpMethod: "PUT", pattern: pattern, handler: wrapHandler[T](handler))

proc delete*[T: object](router: var TsRouter, pattern: string, handler: TypedMatchRequestHandler[T]) =
  router.routes.add Route(httpMethod: "DELETE", pattern: pattern, handler: wrapHandler[T](handler))

proc options*[T: object](router: var TsRouter, pattern: string, handler: TypedMatchRequestHandler[T]) =
  router.routes.add Route(httpMethod: "OPTIONS", pattern: pattern, handler: wrapHandler[T](handler))

proc patch*[T: object](router: var TsRouter, pattern: string, handler: TypedMatchRequestHandler[T]) =
  router.routes.add Route(httpMethod: "PATCH", pattern: pattern, handler: wrapHandler[T](handler))

proc head*[T: object](router: var TsRouter, pattern: string, handler: TypedMatchRequestHandler[T]) =
  router.routes.add Route(httpMethod: "HEAD", pattern: pattern, handler: wrapHandler[T](handler))

# Explicit typedesc overloads (e.g., router.get("/path", Foo, handler))
proc get*[T: object](router: var TsRouter, pattern: string, TVal: typedesc[T], handler: TypedMatchRequestHandler[T]) =
  router.get(pattern, handler)

proc post*[T: object](router: var TsRouter, pattern: string, TVal: typedesc[T], handler: TypedMatchRequestHandler[T]) =
  router.post(pattern, handler)

proc put*[T: object](router: var TsRouter, pattern: string, TVal: typedesc[T], handler: TypedMatchRequestHandler[T]) =
  router.put(pattern, handler)

proc delete*[T: object](router: var TsRouter, pattern: string, TVal: typedesc[T], handler: TypedMatchRequestHandler[T]) =
  router.delete(pattern, handler)

proc options*[T: object](router: var TsRouter, pattern: string, TVal: typedesc[T], handler: TypedMatchRequestHandler[T]) =
  router.options(pattern, handler)

proc patch*[T: object](router: var TsRouter, pattern: string, TVal: typedesc[T], handler: TypedMatchRequestHandler[T]) =
  router.patch(pattern, handler)

proc head*[T: object](router: var TsRouter, pattern: string, TVal: typedesc[T], handler: TypedMatchRequestHandler[T]) =
  router.head(pattern, handler)

# =============================================================================
# With VHost
# =============================================================================

proc get*[T: object](router: var TsRouter, vhost, pattern: string, handler: TypedMatchRequestHandler[T]) =
  router.routes.add Route(vhost: vhost, httpMethod: "GET", pattern: pattern, handler: wrapHandler[T](handler))

proc post*[T: object](router: var TsRouter, vhost, pattern: string, handler: TypedMatchRequestHandler[T]) =
  router.routes.add Route(vhost: vhost, httpMethod: "POST", pattern: pattern, handler: wrapHandler[T](handler))

proc put*[T: object](router: var TsRouter, vhost, pattern: string, handler: TypedMatchRequestHandler[T]) =
  router.routes.add Route(vhost: vhost, httpMethod: "PUT", pattern: pattern, handler: wrapHandler[T](handler))

proc delete*[T: object](router: var TsRouter, vhost, pattern: string, handler: TypedMatchRequestHandler[T]) =
  router.routes.add Route(vhost: vhost, httpMethod: "DELETE", pattern: pattern, handler: wrapHandler[T](handler))

proc options*[T: object](router: var TsRouter, vhost, pattern: string, handler: TypedMatchRequestHandler[T]) =
  router.routes.add Route(vhost: vhost, httpMethod: "OPTIONS", pattern: pattern, handler: wrapHandler[T](handler))

proc patch*[T: object](router: var TsRouter, vhost, pattern: string, handler: TypedMatchRequestHandler[T]) =
  router.routes.add Route(vhost: vhost, httpMethod: "PATCH", pattern: pattern, handler: wrapHandler[T](handler))

proc head*[T: object](router: var TsRouter, vhost, pattern: string, handler: TypedMatchRequestHandler[T]) =
  router.routes.add Route(vhost: vhost, httpMethod: "HEAD", pattern: pattern, handler: wrapHandler[T](handler))

# Explicit typedesc overloads with VHost
proc get*[T: object](router: var TsRouter, vhost, pattern: string, TVal: typedesc[T], handler: TypedMatchRequestHandler[T]) =
  router.get(vhost, pattern, handler)

proc post*[T: object](router: var TsRouter, vhost, pattern: string, TVal: typedesc[T], handler: TypedMatchRequestHandler[T]) =
  router.post(vhost, pattern, handler)

proc put*[T: object](router: var TsRouter, vhost, pattern: string, TVal: typedesc[T], handler: TypedMatchRequestHandler[T]) =
  router.put(vhost, pattern, handler)

proc delete*[T: object](router: var TsRouter, vhost, pattern: string, TVal: typedesc[T], handler: TypedMatchRequestHandler[T]) =
  router.delete(vhost, pattern, handler)

proc options*[T: object](router: var TsRouter, vhost, pattern: string, TVal: typedesc[T], handler: TypedMatchRequestHandler[T]) =
  router.options(vhost, pattern, handler)

proc patch*[T: object](router: var TsRouter, vhost, pattern: string, TVal: typedesc[T], handler: TypedMatchRequestHandler[T]) =
  router.patch(vhost, pattern, handler)

proc head*[T: object](router: var TsRouter, vhost, pattern: string, TVal: typedesc[T], handler: TypedMatchRequestHandler[T]) =
  router.head(vhost, pattern, handler)

# Request Dispatcher
proc handleRequest*(router: TsRouter, request: Request) =
  var params: seq[ParamPair]
  let reqPath = request.uri.parseUrl().path.decodeUrl()

  for route in router.routes:
    if request.httpMethod == route.httpMethod and matchPath(route.pattern, reqPath, params):
      route.handler(request, params)
      return

  var headers: HttpHeaders
  headers["Content-Type"] = "text/plain"
  request.respond(404, headers, "404 Not Found")

proc toHandler*(tsRouter: TsRouter): RequestHandler =
  return proc(request: Request) {.gcsafe.} =
    var routeMatched = false
    var fullyMatched = false
    var params: seq[ParamPair]

    try:
      # Fix URI to extract virtual host if present
      let fixUri = ("https://" & request.headers["Host"]).parseUri()
      let host = fixUri.hostname
      let reqPath = request.uri.parseUrl().path.decodeUrl()

      for route in tsRouter.routes:
        # Check virtual host if specified
        if route.vhost.len != 0 and route.vhost != host:
          continue

        # Match path and extract named URL parameters
        if matchPath(route.pattern, reqPath, params):
          routeMatched = true
          if request.httpMethod == route.httpMethod:
            fullyMatched = true
            route.handler(request, params)
            break

      if not routeMatched:
        tsRouter.notFoundHandler(request)
      elif not fullyMatched:
        # Route matched pattern, but HTTP verb didn't match
        tsRouter.methodNotAllowedHandler(request)

    except CatchableError as e:
      # tsRouter.errorHandler(request, e)
      tsRouter.errorHandler(request)

# Converter for automatic Mummy compatibility
converter convertToHandler*(tsRouter: TsRouter): RequestHandler =
  tsRouter.toHandler()

# when isMainModule:
#
#   import unittest
#   suite "TSRouter":
#     test "match":
#
#       var params: seq[ParamPair]
#       check true == matchPath("/login/@user/@id", "/login/USERNAME/123", params)
#       check params.len == 2
#       check params[0] == ("user", "USERNAME")
#       check params[1] == ("id", "123")
#
#       type
#         User = object
#           user: string
#           id: int
#       let obj = unpackNamedParams[User](params)
#       check obj.user == "USERNAME"
#       check obj.id == 123
#  
#
#   type
#     KlausDieter = object
#       kd: string
#
#     Foo = object
#       mybool: bool
#       myint: int
#       myabsint: Natural
#       myfloat: float
#       mystring: string
#       mycustom: KlausDieter
#
#     BaaEnum = enum
#       EBa
#       EBaa
#       EBaaa
#     Baa = object
#       mybool: bool
#       myint: int16
#       myrange: 10 .. 150
#       myenum: BaaEnum
#
#   proc unpackValue*(str: string, val: var KlausDieter) = 
#     if not str.startsWith("KD"):
#       raise newException(ValueError, "Invalid klaus dieter!!")
#     val.kd = str[2..^1]
#
#   proc fooDumpHandler(request: Request, data: Foo) {.gcsafe.} =
#     var headers: HttpHeaders
#     headers["Content-Type"] = "text/plain"
#     request.respond(200, headers, "Successfully parsed Foo: " & $data)
#
#   proc baaDumpHandler(request: Request, data: Baa) {.gcsafe.} =
#     var headers: HttpHeaders
#     headers["Content-Type"] = "text/plain"
#     request.respond(200, headers, "Successfully parsed Baa: " & $data)
#
#   var router = TsRouter()
#
#   # Route parameters match Foo field names explicitly
#   router.get("/foo/@mystring/@myint/@myfloat/@mybool/@myabsint/@mycustom", fooDumpHandler)
#   # router.post("/baa/@mybool/@myint", baaDumpHandler)
#   router.get("/baa/@mybool/@myint/@myrange/@myenum", baaDumpHandler)
#
#
#   type
#     UserRole = enum
#       urAdmin = "admin"
#       urUser = "user"
#       urGuest = "guest"
#
#     RoleQuery = object
#       role: UserRole
#       id: Natural
#
#   proc handleRole(req: Request, data: RoleQuery) {.gcsafe.} =
#     var headers: HttpHeaders
#     headers["Content-Type"] = "text/plain"
#     req.respond(200, headers, "Role: " & $data.role & ", ID: " & $data.id)
#
#   router.get("/role/@role/@id", handleRole)
#   router.post("/role/@role/@id", RoleQuery, handleRole)
#
#   let server = newServer(router)
#   server.serve(Port(9090))
#
#
when isMainModule:
  import unittest, strutils, mummy

  type
    KlausDieter = object
      kd: string

    Foo = object
      mybool: bool
      myint: int
      myabsint: Natural
      myfloat: float
      mystring: string
      mycustom: KlausDieter

    BaaEnum = enum
      EBa
      EBaa
      EBaaa

    Baa = object
      mybool: bool
      myint: int16
      myrange: 10 .. 150
      myenum: BaaEnum

    UserRole = enum
      urAdmin = "admin"
      urUser = "user"
      urGuest = "guest"

    RoleQuery = object
      role: UserRole
      id: Natural

  # Custom unpackValue procedure overload
  proc unpackValue*(str: string, val: var KlausDieter) = 
    if not str.startsWith("KD"):
      raise newException(ValueError, "Invalid Klaus Dieter string format!")
    val.kd = str[2..^1]

  suite "TsRouter Unit Tests":

    test "Path matching & named param extraction":
      var params: seq[ParamPair]
      check matchPath("/login/@user/@id", "/login/USERNAME/123", params) == true
      check params.len == 2
      check params[0] == ("user", "USERNAME")
      check params[1] == ("id", "123")

      type SimpleUser = object
        user: string
        id: int

      let obj = unpackNamedParams[SimpleUser](params)
      check obj.user == "USERNAME"
      check obj.id == 123

    test "Unpacking complex objects & custom types":
      var params = @[
        ("mystring", "hello"),
        ("myint", "-42"),
        ("myfloat", "3.14"),
        ("mybool", "true"),
        ("myabsint", "100"),
        ("mycustom", "KD_Master")
      ]
      
      let fooObj = unpackNamedParams[Foo](params)
      check fooObj.mystring == "hello"
      check fooObj.myint == -42
      check fooObj.myfloat == 3.14
      check fooObj.mybool == true
      check fooObj.myabsint == 100
      check fooObj.mycustom.kd == "_Master"

    test "Unpacking Enums and Subranges":
      var params = @[
        ("mybool", "false"),
        ("myint", "1024"),
        ("myrange", "50"),
        ("myenum", "EBaa")
      ]

      let baaObj = unpackNamedParams[Baa](params)
      check baaObj.mybool == false
      check baaObj.myint == 1024
      check baaObj.myrange == 50
      check baaObj.myenum == EBaa

    test "Validation failures (Invalid Enum / Subrange Out-of-Bounds)":
      var badRangeParams = @[
        ("mybool", "true"),
        ("myint", "10"),
        ("myrange", "5"), # Out of bounds (10..150)
        ("myenum", "EBa")
      ]
      expect(CatchableError):
        discard unpackNamedParams[Baa](badRangeParams)

      var badEnumParams = @[
        ("role", "superadmin"), # Invalid enum variant
        ("id", "10")
      ]
      expect(CatchableError):
        discard unpackNamedParams[RoleQuery](badEnumParams)

    # test "TODO Full Router Request Dispatch (toHandler)":
    #   raise
    #   var router = TsRouter()
    #
    #   # Track handler execution via side effects
    #   var fooCalled = false
    #   var roleCalled = false
    #
    #   proc fooDumpHandler(request: Request, data: Foo) {.gcsafe.} =
    #     fooCalled = true
    #     check data.mystring == "test"
    #     check data.myint == 7
    #     check data.mycustom.kd == "123"
    #     # request.respond(200, newHttpHeaders(@[(key: "Content-Type", value: "text/plain")]), "OK") # TODO
    #
    #   proc handleRole(req: Request, data: RoleQuery) {.gcsafe.} =
    #     roleCalled = true
    #     check data.role == urAdmin
    #     check data.id == 99
    #     # req.respond(200, @[Header(key: "Content-Type", value: "text/plain")], "OK")
    #
    #   router.get("/foo/@mystring/@myint/@myfloat/@mybool/@myabsint/@mycustom", fooDumpHandler)
    #   router.post("/role/@role/@id", RoleQuery, handleRole)
    #
    #   let handler = router.toHandler()
    #
    #   ## TODO 
    #   # # 1. Test GET /foo/... route dispatch
    #   # var req1 = Request(
    #   #   httpMethod: "GET",
    #   #   uri: "/foo/test/7/2.718/true/42/KD123",
    #   #   headers: @[Header(key: "Host", value: "localhost")]
    #   # )
    #   # handler(req1)
    #   # check fooCalled == true
    # #
    # #   # 2. Test POST /role/... route dispatch
    # #   var req2 = Request(
    # #     httpMethod: "POST",
    # #     uri: "/role/admin/99",
    # #     headers: @[Header(key: "Host", value: "localhost")]
    # #   )
    # #   handler(req2)
    # #   check roleCalled == true
