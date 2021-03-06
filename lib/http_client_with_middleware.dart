import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:http/http.dart';
import 'package:http/io_client.dart';
import 'package:http_middleware/http_methods.dart';
import 'package:http_middleware/models/request_data.dart';
import 'package:http_middleware/models/response_data.dart';
import 'middleware_contract.dart';

///Class to be used by the user to set up a new `http.Client` with middleware supported.
///call the `build()` constructor passing in the list of middlewares.
///Example:
///```dart
/// HttpClientWithMiddleware httpClient = HttpClientWithMiddleware.build(middlewares: [
///     Logger(),
/// ]);
///```
///
///Then call the functions you want to, on the created `http` object.
///```dart
/// httpClient.get(...);
/// httpClient.post(...);
/// httpClient.put(...);
/// httpClient.delete(...);
/// httpClient.head(...);
/// httpClient.patch(...);
/// httpClient.read(...);
/// httpClient.readBytes(...);
/// httpClient.send(...);
/// httpClient.close();
///```
///Don't forget to close the client once you are done, as a client keeps
///the connection alive with the server.
class HttpClientWithMiddleware extends http.BaseClient {
  List<MiddlewareContract>? middlewares;
  Duration? requestTimeout;

  final IOClient _client = IOClient();

  HttpClientWithMiddleware._internal({this.middlewares, this.requestTimeout});

  factory HttpClientWithMiddleware.build({
    List<MiddlewareContract>? middlewares,
    Duration? requestTimeout,
  }) {
    //Remove any value that is null.
    middlewares?.removeWhere((middleware) => middleware == null);
    return HttpClientWithMiddleware._internal(
      middlewares: middlewares,
      requestTimeout: requestTimeout,
    );
  }

  Future<Response> head(url, {Map<String, String>? headers}) => _sendUnstreamed("HEAD", url, headers);

  Future<Response> get(url, {Map<String, String>? headers}) => _sendUnstreamed("GET", url, headers);

  Future<Response> post(url, {Map<String, String>? headers, body, Encoding? encoding}) =>
      _sendUnstreamed("POST", url, headers, body, encoding);

  Future<Response> put(url, {Map<String, String>? headers, body, Encoding? encoding}) => _sendUnstreamed("PUT", url, headers, body, encoding);

  Future<Response> patch(url, {Map<String, String>? headers, body, Encoding? encoding}) =>
      _sendUnstreamed("PATCH", url, headers, body, encoding);

  Future<Response> delete(url, {Map<String, String>? headers, body, Encoding? encoding}) =>
      _sendUnstreamed("DELETE", url, headers, body, encoding);

  Future<String> read(url, {Map<String, String>? headers}) {
    return get(url, headers: headers).then((response) {
      _checkResponseSuccess(url, response);
      return response.body;
    });
  }

  Future<Uint8List> readBytes(url, {Map<String, String>? headers}) {
    return get(url, headers: headers).then((response) {
      _checkResponseSuccess(url, response);
      return response.bodyBytes;
    });
  }

  Future<StreamedResponse> send(BaseRequest request) => _client.send(request);

  Future<Response> _sendUnstreamed(String method, url, Map<String, String>? headers, [body, Encoding? encoding]) async {
    if (url is String) url = Uri.parse(url);
    var request = new Request(method, url);

    if (headers != null) request.headers.addAll(headers);
    if (encoding != null) request.encoding = encoding;
    if (body != null) {
      if (body is String) {
        request.body = body;
      } else if (body is List) {
        request.bodyBytes = DelegatingList.typed(body);
      } else if (body is Map) {
        request.bodyFields = DelegatingMap.typed(body);
      } else {
        throw new ArgumentError('Invalid request body "$body".');
      }
    }

    //Send interception
    middlewares?.forEach(
      (middleware) => middleware.interceptRequest(
        data: RequestData(
          method: methodFromString(method),
          encoding: encoding,
          body: body,
          url: url.toString(),
          headers: headers ?? <String, String>{},
        ),
      ),
    );

    var stream = requestTimeout == null ? await send(request) : await send(request).timeout(requestTimeout!);

    return Response.fromStream(stream).then((response) {
      var responseData = ResponseData.fromHttpResponse(response);

      middlewares?.forEach((middleware) => middleware.interceptResponse(data: responseData));

      Response resultResponse = Response(
        responseData.body!,
        responseData.statusCode!,
        headers: responseData.headers!,
        persistentConnection: responseData.persistentConnection!,
        isRedirect: responseData.isRedirect!,
        request: Request(
          responseData.method.toString().substring(7),
          Uri.parse(responseData.url!),
        ),
      );

      return resultResponse;
    });
  }

  void _checkResponseSuccess(url, Response response) {
    if (response.statusCode < 400) return;
    var message = "Request to $url failed with status ${response.statusCode}";
    if (response.reasonPhrase != null) {
      message = "$message: ${response.reasonPhrase}";
    }
    if (url is String) url = Uri.parse(url);
    throw new ClientException("$message.", url);
  }

  void close() {
    _client.close();
  }
}
