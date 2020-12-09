library html_editor;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html_editor/local_server.dart';
import 'package:webview_flutter/webview_flutter.dart';

/*
 * Created by riyadi rb on 2/5/2020.
 * link  : https://github.com/xrb21/flutter-html-editor
 */

typedef void OnClik();

class HtmlEditor extends StatefulWidget {
  final String value;
  final double height;
  final BoxDecoration decoration;
  final bool useBottomSheet;
  final String widthImage;
  final bool showBottomToolbar;
  final String hint;
  final String defaultPage;
  final dynamic imageSelector;

  HtmlEditor({
    Key key,
    this.value,
    this.height = 380,
    this.decoration,
    this.useBottomSheet = true,
    this.widthImage = "100%",
    this.showBottomToolbar = true,
    this.defaultPage,
    this.imageSelector,
    this.hint
  })
      : super(key: key);

  @override
  HtmlEditorState createState() => HtmlEditorState();
}

class HtmlEditorState extends State<HtmlEditor> {
  WebViewController _controller;
  String text = "";
  final Key _mapKey = UniqueKey();

  bool _pageLoaded = false;

  int port = 5321;
  LocalServer localServer;

  @override
  void initState() {
    if (!Platform.isAndroid) {
      initServer();
    }
    super.initState();
  }

  initServer() {
    localServer = LocalServer(port);
    localServer.start(handleRequest);
  }

  void handleRequest(HttpRequest request) {
    try {
      if (request.method == 'GET' &&
          request.uri.queryParameters['query'] == "getRawTeXHTML") {
      } else {}
    } catch (e) {
      print('Exception in handleRequest: $e');
    }
  }

  @override
  void dispose() {
    if (_controller != null) {
      _controller = null;
    }
    if (!Platform.isAndroid) {
      localServer.close();
    }
    super.dispose();
  }

  _loadHtmlFromAssets() async {
    final filePath = 'packages/html_editor/summernote/summernote.html';
    _controller.loadUrl("http://localhost:$port/$filePath");
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: widget.decoration ??
          BoxDecoration(
            borderRadius: BorderRadius.all(Radius.circular(4)),
            border: Border.all(color: Color(0xffececec), width: 1),
          ),
      child: Column(
        children: <Widget>[
          !_pageLoaded ? Container() :
            Padding(
              padding: const EdgeInsets.only(left: 10, right: 10, bottom: 5, top: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  widgetIcon(Icons.image, onKlik: () async{
                    await SystemChannels.textInput.invokeMethod('TextInput.hide');
                    widget.useBottomSheet
                        ? bottomSheetPickImage(context)
                        : dialogPickImage(context);
                  }),
                  Container(width: 5,),
                  widgetIcon(Icons.content_copy, onKlik: () async {
                    String data = await getText();
                    Clipboard.setData(new ClipboardData(text: data));
                  }),
                  Container(width: 5,),
                  widgetIcon(Icons.content_paste,
                      onKlik: () async {
                    ClipboardData data =
                        await Clipboard.getData(Clipboard.kTextPlain);

                    String txtIsi = data.text
                        .replaceAll("'", '\\"')
                        .replaceAll('"', '\\"')
                        .replaceAll("[", "\\[")
                        .replaceAll("]", "\\]")
                        .replaceAll("\n", "<br/>")
                        .replaceAll("\n\n", "<br/>")
                        .replaceAll("\r", " ")
                        .replaceAll('\r\n', " ");
                    var txt = '''
                      var div = document.createElement('div');
                      div.innerHTML = 
                        "<div>" +
                          "$txtIsi" +
                        "</div>";
                      \$('#summernote').summernote('insertNode', div.firstChild);
                    ''';
                    
                    await setFocus();
                    await _controller.evaluateJavascript(txt);
                  }),
                  Container(width: 5,),
                  widgetIcon(Icons.delete_outline, onKlik: () async {
                    await setEmpty();
                  }),
                  Container(width: 5,),
                  widgetIcon(Icons.undo, onKlik: () async {
                    await undo();
                  }),
                  Container(width: 5,),
                  widgetIcon(Icons.redo, onKlik: () async {
                    await redo();
                  }),
                ],
              ),
            ),
          Expanded(
            child: WebView(
              key: _mapKey,
              onWebResourceError: (e) {
                print("error ${e.description}");
              },
              onWebViewCreated: (webViewController) {
                _controller = webViewController;

                if(widget.defaultPage != null){
                  final String contentBase64 = base64Encode(const Utf8Encoder().convert(widget.defaultPage));
                  _controller.loadUrl('data:text/html;base64,$contentBase64');
                }else{
                  if (Platform.isAndroid) {
                  final filename =
                      'packages/html_editor/summernote/summernote.html';
                    _controller.loadUrl(
                        "file:///android_asset/flutter_assets/" + filename);
                  } else {
                    _loadHtmlFromAssets();
                  }
                }
              },
              javascriptMode: JavascriptMode.unrestricted,
              gestureNavigationEnabled: true,
              gestureRecognizers: [
                Factory(
                    () => VerticalDragGestureRecognizer()..onUpdate = (_) {}),
              ].toSet(),
              javascriptChannels: <JavascriptChannel>[
                getTextJavascriptChannel(context)
              ].toSet(),
              onPageFinished: (String url) {
                if (widget.hint != null) {
                  setHint(widget.hint);
                } else {
                  setHint("");
                }

                setFullContainer();
                if (widget.value != null) {
                  setText(widget.value);
                }
                setState(() {
                  _pageLoaded = true;
                });
              },
            ),
          ),   
          Container(height: 5,),
        ],
      ),
    );
  }

  JavascriptChannel getTextJavascriptChannel(BuildContext context) {
    return JavascriptChannel(
        name: 'GetTextSummernote',
        onMessageReceived: (JavascriptMessage message) {
          String isi = message.message;
          if (isi.isEmpty ||
              isi == "<p></p>" ||
              isi == "<p><br></p>" ||
              isi == "<p><br/></p>") {
            isi = "";
          }
          setState(() {
            text = isi;
          });
        });
  }

  Future<String> getText() async {
    await _controller.evaluateJavascript(
        "GetTextSummernote.postMessage(document.getElementsByClassName('note-editable')[0].innerHTML);");
    return text;
  }

  setText(String v) async {
    String txtIsi = v
        .replaceAll("'", '\\"')
        .replaceAll('"', '\\"')
        .replaceAll("[", "\\[")
        .replaceAll("]", "\\]")
        .replaceAll("\n", "<br/>")
        .replaceAll("\n\n", "<br/>")
        .replaceAll("\r", " ")
        .replaceAll('\r\n', " ");
    String txt =
        "document.getElementsByClassName('note-editable')[0].innerHTML = '" +
            txtIsi +
            "';";
    _controller.evaluateJavascript(txt);
  }

  setFullContainer() {
    _controller.evaluateJavascript(
        '\$("#summernote").summernote("fullscreen.toggle");');
  }

  Future<void> setFocus() async{
    await _controller.evaluateJavascript("\$('#summernote').summernote('focus');");
  }

  Future<void> setEmpty() async{
    await _controller.evaluateJavascript("\$('#summernote').summernote('reset');");
  }

  Future<void> undo() async{
    await _controller.evaluateJavascript("\$('#summernote').summernote('undo');");
  }

  Future<void> redo() async{
    await _controller.evaluateJavascript("\$('#summernote').summernote('redo');");
  }

  setHint(String text) {
    String hint = '\$(".note-placeholder").html("$text");';
    _controller.evaluateJavascript(hint);
  }

  WebViewController getController() => _controller;

  Widget widgetIcon(IconData icon, {OnClik onKlik}) {
    return InkWell(
      onTap: () async{
        if(onKlik != null){
          onKlik();
        }
      },
      child: Container(
        padding: EdgeInsets.only(left: 8, right: 8, top: 3, bottom: 3),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black12, width: 1),
          borderRadius: BorderRadius.all(Radius.circular(4))
        ),
        child: Icon(icon, size: 20, color: Colors.black54,)
      )
    );
  }

  dialogPickImage(BuildContext context) {
    return showDialog(
        context: context,
        barrierDismissible: true,
        builder: (BuildContext context) {
          return AlertDialog(
            elevation: 0,
            backgroundColor: Colors.transparent,
            content: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
              padding: const EdgeInsets.all(12),
              height: 240,
              width: 320,
              child: widget.imageSelector,
              /*
              PickImage(
                color: Colors.black45,
                callbackFile: (file) async {
                  String filename = p.basename(file.path);
                  List<int> imageBytes = await file.readAsBytes();
                  String base64Image =
                      "<img width=\"${widget.widthImage}\" src=\"data:image/png;base64, "
                      "${base64Encode(imageBytes)}\" data-filename=\"$filename\">";

                  String txt =
                      "\$('.note-editable').append( '" + base64Image + "');";
                  _controller.evaluateJavascript(txt);
                }
              )
               */
            ),
          );
        });
  }

  bottomSheetPickImage(context) {
    showModalBottomSheet(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        backgroundColor: Colors.white,
        context: context,
        builder: (BuildContext bc) {
          return StatefulBuilder(builder: (BuildContext context, setStatex) {
            return SingleChildScrollView(
                child: Container(
              height: 140,
              width: double.infinity,
              child: widget.imageSelector,
              /*
              PickImage(callbackFile: (file) async {
                String filename = p.basename(file.path);
                List<int> imageBytes = await file.readAsBytes();
                String base64Image = "<img width=\"${widget.widthImage}\" "
                    "src=\"data:image/png;base64, "
                    "${base64Encode(imageBytes)}\" data-filename=\"$filename\">";
                String txt =
                    "\$('.note-editable').append( '" + base64Image + "');";
                _controller.evaluateJavascript(txt);
              }),
              */
            ));
          });
        });
  }
}
