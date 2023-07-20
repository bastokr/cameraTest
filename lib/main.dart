import 'dart:ffi';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:image/image.dart' as imglib;
import 'package:camera/camera.dart';
import 'package:object_detection_ssd_mobilenet/yuv_chanelling.dart';

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  _cameras = await availableCameras();
  runApp(const CameraApp());
}

/// CameraApp is the Main Application.
class CameraApp extends StatefulWidget {
  /// Default Constructor
  const CameraApp({Key? key}) : super(key: key);

  @override
  State<CameraApp> createState() => _CameraAppState();
}

class _CameraAppState extends State<CameraApp> {
  late CameraController controller;
  late CameraImage _savedImage;
  late Uint8List _image;
  void _processImageFromStream(CameraImage image) {
    print(image.planes[0].bytes[0]);

    _savedImage = image;
  }

  @override
  void initState() {
    super.initState();
    controller = CameraController(_cameras[0], ResolutionPreset.low,
        enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
    controller.initialize().then((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    }).catchError((Object e) {
      if (e is CameraException) {
        switch (e.code) {
          case 'CameraAccessDenied':
            print('User denied camera access.');
            break;
          default:
            print('Handle other errors.');
            break;
        }
      }
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return Container();
    }
    return MaterialApp(
        home: Scaffold(
            floatingActionButton: Column(
              children: [
                SizedBox(height: 200),
                FloatingActionButton(onPressed: () {
                  if (controller.value.isStreamingImages) {
                    print('Stopping image stream');
                    controller.stopImageStream();
                  } else {
                    print('Starting new image stream');
                    controller.startImageStream(_processImageFromStream);
                  }
                }),
                FloatingActionButton(
                  onPressed: () {
                    convertImageToPng(_savedImage);
                  },
                  tooltip: 'Increment',
                  child: Icon(Icons.camera_alt),
                ),

                // This trailing comma makes auto-formatting nicer for build methods.
              ],
            ),
            body: Column(children: [
              Image.memory(_image),
              Expanded(child: CameraPreview(controller)),
            ])));
  }

  void _processCameraImage(CameraImage image) async {
    setState(() {
      _savedImage = image;
    });
  }

  Future<Uint8List?> convertImageToPng(CameraImage image) async {
    Uint8List? bytes;
    controller.stopImageStream();
    try {
      imglib.Image img;
      if (image.format.group == ImageFormatGroup.bgra8888) {
        img = _convertBGRA8888(image);
        imglib.PngEncoder pngEncoder = new imglib.PngEncoder();
        bytes = pngEncoder.encode(img);
      } else {
        bytes = await convertYUV420toImageColor(image);
        print(bytes);
        _image = bytes!;
      }
      print(bytes);
      return bytes;
    } catch (e) {
      print(">>>>>>>>>>>> ERROR:" + e.toString());
    }
    return null;
  }

  imglib.Image _convertBGRA8888(CameraImage image) {
    return imglib.Image.fromBytes(
        width: image.width,
        height: image.height,
        bytes: image.planes[0].bytes.buffer,
        order: imglib.ChannelOrder.bgra);
  }

  Future<Uint8List> convertImageToJPG(CameraImage image) async {
    YuvChannelling _yuvChannelling = YuvChannelling();
    Uint8List imgJpeg = await _yuvChannelling.yuv_transform(image);
    return imgJpeg;
  }

  static const shift = (0xFF << 24);
  Future<Uint8List?> convertYUV420toImageColor(CameraImage image) async {
    try {
      final int width = image.width;
      final int height = image.height;
      final int uvRowStride = image.planes[1].bytesPerRow;
      final int? uvPixelStride = image.planes[1].bytesPerPixel;

      print("uvRowStride: " + uvRowStride.toString());
      print("uvPixelStride: " + uvPixelStride.toString());

      // imgLib -> Image package from https://pub.dartlang.org/packages/image
      var img =
          imglib.Image(width: width, height: height); // Create Image buffer

      // Fill image buffer with plane[0] from YUV420_888
      for (int x = 0; x < width; x++) {
        for (int y = 0; y < height; y++) {
          final int uvIndex =
              uvPixelStride! * (x / 2).floor() + uvRowStride * (y / 2).floor();
          final int index = y * width + x;

          final yp = image.planes[0].bytes[index];
          final up = image.planes[1].bytes[uvIndex];
          final vp = image.planes[2].bytes[uvIndex];
          // Calculate pixel color
          int r = (yp + vp * 1436 / 1024 - 179).round().clamp(0, 255);
          int g = (yp - up * 46549 / 131072 + 44 - vp * 93604 / 131072 + 91)
              .round()
              .clamp(0, 255);
          int b = (yp + up * 1814 / 1024 - 227).round().clamp(0, 255);
          // color: 0x FF  FF  FF  FF
          //           A   B   G   R
          //img.data[index] = shift | (b << 16) | (g << 8) | r;

          if (img.isBoundsSafe(height - y, x)) {
            img.setPixelRgba(height - y, x, r, g, b, shift);
          }
        }
      }

      var pngEncoder = imglib.PngEncoder(level: 0);
      var png = pngEncoder.encode(img);
      //  muteYUVProcessing = false;
      //return Image.memory(png);
      return png;
    } catch (e) {
      print(">>>>>>>>>>>> ERROR:" + e.toString());
    }
    return null;
  }

  imglib.Image _convertYUV420(CameraImage image) {
    var img = imglib.Image(
        width: image.width, height: image.height); // Create Image buffer

    Plane plane = image.planes[0];

    const int shift = (0xFF << 24);

    // Fill image buffer with plane[0] from YUV420_888

    for (int x = 0; x < image.width; x++) {
      for (int planeOffset = 0;
          planeOffset < image.height * image.width;
          planeOffset += image.width) {
        final pixelColor = plane.bytes[planeOffset + x];

        // color: 0x FF  FF  FF  FF

        //           A   B   G   R

        // Calculate pixel color

        var newVal =
            shift | (pixelColor << 16) | (pixelColor << 8) | pixelColor;

        //img.data?[planeOffset + x] = newVal;
      }
    }

    return img;
  }
}
