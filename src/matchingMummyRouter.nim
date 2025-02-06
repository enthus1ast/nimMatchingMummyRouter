import mummy, mummy/routers
import urlMatcher
export urlMatcher
import strutils, os, mimetypes

when not defined(release):
  import print

type 
  MatchRequestHandler* = proc (request: Request, mt: MatchTable) {.gcsafe.}
  MatchRoute* = object
    vhost: string
    httpMethod: string
    matcher: string
    handler: MatchRequestHandler
  MatchRouter* = object
    routes: seq[MatchRoute]
    notFoundHandler*: RequestHandler
    methodNotAllowedHandler*: MatchRequestHandler
    errorHandler*: RequestErrorHandler

when (NimMajor, NimMinor, NimPatch) >= (1,9,3):
  # Mimetypes is a ref on older versions
  const m = newMimetypes()

proc defaultNotFound*(request: Request) =
  var headers: HttpHeaders
  headers["Content-Type"] = "text/plain"
  request.respond(404, headers, "not found")

proc defaultForbidden*(request: Request) =
  var headers: HttpHeaders
  headers["Content-Type"] = "text/plain"
  request.respond(403, headers, "forbidden")

proc staticFileHandler*(request: Request, mt: MatchTable) =
  ## Static file handler
  var path = request.uri.decodeUrl()
  # var path = mt["**"]
  var headers: HttpHeaders

  if path.contains(".."):
    # return404
    # callNotFoundHandler ## how to get the router from a handler?
    defaultNotFound(request)
    return

  let ext = path.splitFile().ext

  when (NimMajor, NimMinor, NimPatch) <= (1,9,3):
    # Mimetypes is a ref on older versions
    let m = newMimetypes()
  let mimetype = m.getMimeType(ext)
  let filePath = getAppDir() / path


  when not defined(release):
    {.gcsafe.}:
      print path, request.uri, ext, mimetype, filePath

  if not fileExists(filePath):
    defaultNotFound(request)
    return

  var fp = getFilePermissions(filePath)
  if not fp.contains(fpOthersRead):
    defaultForbidden(request)
    return

  headers["Content-Type"] = mimetype
  headers["Connection"] = "close"
  request.respond(200, headers, readFile(filePath))

proc defaultMethodNotAllowed*(request: Request, mt: MatchTable) =
  var headers: HttpHeaders
  headers["Content-Type"] = "text/plain"
  request.respond(405, headers, "method not allowed")

proc defaultErrorHandler*(request: Request, mt: MatchTable) =
  var headers: HttpHeaders
  headers["Content-Type"] = "text/plain"
  request.respond(405, headers, "method not allowed")

proc callMethodNotAllowedHandler(matchRouter: MatchRouter, request: Request, mt: MatchTable) =
  if matchRouter.methodNotAllowedHandler != nil:
    # Call user supplied methodNotAllowedHandler
    matchRouter.methodNotAllowedHandler(request, mt)
  else:
    # Call default methodNotAllowedHandler
    defaultMethodNotAllowed(request, mt)

proc callNotFoundHandler(matchRouter: MatchRouter, request: Request) =
  if matchRouter.notFoundHandler != nil:
    # Call user supplied not found handler
    matchRouter.notFoundHandler(request)
  else:
    # Call default not found handler
    defaultNotFound(request)

proc callErrorHandler(matchRouter: MatchRouter, request: Request, e: ref Exception) = 
  if matchRouter.errorHandler != nil:
    # Call the error handler if we have any
    matchRouter.errorHandler(request, e)
  else:
    raise(e) # forward the error

import print

proc toHandler*(matchRouter: MatchRouter): RequestHandler =
  return proc(request: Request) {.gcsafe.} =
    var oneMatched = false
    var fullyMatched = false
    try:
      var mt = newMatchTable()
      for mr in matchRouter.routes:
        mt.clear()
        # echo "mr.vhost:", mr.vhost
        # echo "request.header[Host]: ", request.headers["Host"]
        # echo "request.header: ", request.headers

        ## Parse uri expects a schema:
        let fixuri = ("https://" & request.headers["Host"]).parseUri()
        let host = fixuri.hostname
        # echo "HOST (fixed):", host
        # echo "request.header: ", request.headers["Host"].parseUri()
        {.cast(gcsafe).}:
          # print request.headers["Host"].parseUri()
          # print host
        if mr.vhost.len != 0: # if a vhost is specified
          if mr.vhost != host:  #request.headers["Host"]:
            continue # if vhost does not match
        if match(request.uri, mr.matcher, mt):
          if request.httpMethod == mr.httpMethod:
            # Route + httpMethod matched 
            mr.handler(request, mt)
            oneMatched = true
            fullyMatched = true
            break
          else:
            # Route matched but httpMethod not
            oneMatched = true

      if not oneMatched:
        matchRouter.callNotFoundHandler(request)
      elif not fullyMatched:
        matchRouter.callMethodNotAllowedHandler(request, mt)

    except:
      let e = getCurrentException()
      matchRouter.callErrorHandler(request, e)

proc get*(matchRouter: var MatchRouter, matcher: string, vhost: string, handler: MatchRequestHandler) =
  matchRouter.routes.add MatchRoute(httpMethod: "GET", matcher: matcher, vhost: vhost, handler: handler)
    
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
