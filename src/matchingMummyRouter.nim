import mummy, mummy/routers
import urlMatcher
export urlMatcher


type 
  MatchRequestHandler* = proc (request: Request, mt: MatchTable) {.gcsafe.}
  MatchRoute* = object
    httpMethod: string
    matcher: string
    handler: MatchRequestHandler
  MatchRouter* = object
    routes: seq[MatchRoute]
    notFoundHandler*: RequestHandler
    methodNotAllowedHandler*: MatchRequestHandler
    errorHandler*: RequestErrorHandler

proc defaultNotFound*(request: Request) =
  var headers: HttpHeaders
  headers["Content-Type"] = "text/plain"
  request.respond(404, headers, "not found")

proc defaultMethodNotAllowed*(request: Request, mt: MatchTable) =
  var headers: HttpHeaders
  headers["Content-Type"] = "text/plain"
  request.respond(405, headers, "method not allowed")

proc toHandler*(matchRouter: MatchRouter): RequestHandler =
  return proc(request: Request)  {.gcsafe.} =
    var oneMatched = false
    try:
      for mr in matchRouter.routes:
        var mt = newMatchTable()
        if match(request.uri, mr.matcher, mt):
          if request.httpMethod == mr.httpMethod:
            # Route + httpMethod matched 
            mr.handler(request, mt)
            oneMatched = true
            break
          else:
            # Route matched but httpMethod not
            oneMatched = true
            if matchRouter.methodNotAllowedHandler != nil:
              # Call user supplied methodNotAllowedHandler
              matchRouter.methodNotAllowedHandler(request, mt)
            else:
              # Call default methodNotAllowedHandler
              defaultMethodNotAllowed(request, mt)
            break
      if not oneMatched:
        echo "NOT MATCHED"
        if matchRouter.notFoundHandler != nil:
          # Call user supplied not found handler
          matchRouter.notFoundHandler(request)
        else:
          # Call default not found handler
          defaultNotFound(request)
    except:
      let e = getCurrentException()
      if matchRouter.errorHandler != nil:
        # Call the error handler if we have any
        matchRouter.errorHandler(request, e)
      else:
        raise(e) # forward the error
    
proc get*(matchRouter: var MatchRouter, matcher: string, handler: MatchRequestHandler) =
  matchRouter.routes.add MatchRoute(httpMethod: "GET", matcher: matcher, handler: handler)

proc post*(matchRouter: var MatchRouter, matcher: string, handler: MatchRequestHandler) =
  matchRouter.routes.add MatchRoute(httpMethod: "POST", matcher: matcher, handler: handler)

proc put*(matchRouter: var MatchRouter, matcher: string, handler: MatchRequestHandler) =
  matchRouter.routes.add MatchRoute(httpMethod: "PUT", matcher: matcher, handler: handler)

proc delete*(matchRouter: var MatchRouter, matcher: string, handler: MatchRequestHandler) =
  matchRouter.routes.add MatchRoute(httpMethod: "DELETE", matcher: matcher, handler: handler)

proc options*(matchRouter: var MatchRouter, matcher: string, handler: MatchRequestHandler) =
  matchRouter.routes.add MatchRoute(httpMethod: "OPTIONS", matcher: matcher, handler: handler)

proc patch*(matchRouter: var MatchRouter, matcher: string, handler: MatchRequestHandler) =
  matchRouter.routes.add MatchRoute(httpMethod: "PATCH", matcher: matcher, handler: handler)

converter convertToHandler*(matchRouter: MatchRouter): RequestHandler =
  matchRouter.toHandler()
