import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
Widget embedPreview(String url)=>HtmlElementView.fromTagName(key:ValueKey(url),tagName:'iframe',onElementCreated:(element){
 final frame=element as web.HTMLIFrameElement;
 frame.src=url;frame.title='Reports chart';frame.style.border='0';frame.style.width='100%';frame.style.height='100%';
});
