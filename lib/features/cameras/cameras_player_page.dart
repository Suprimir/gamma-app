import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../data/api_client.dart';
import '../../ui/shared_widgets.dart';

class CameraPlayerPage extends StatefulWidget {
  const CameraPlayerPage({super.key, required this.api, required this.camera});

  final ApiClient api;
  final Map<String, dynamic> camera;

  @override
  State<CameraPlayerPage> createState() => _CameraPlayerPageState();
}

class _CameraPlayerPageState extends State<CameraPlayerPage> {
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  Player? _player;
  VideoController? _videoController;
  String _mode = 'live';
  String _state = 'conectando';
  String? _error;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _renderer.initialize();
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = 'error';
          _error = e.toString();
        });
      }
      return;
    }
    if (mounted) await _connect();
  }

  @override
  void dispose() {
    _teardown();
    _teardownHd();
    _renderer.dispose();
    super.dispose();
  }

  Future<void> _teardown() async {
    final pc = _pc;
    _pc = null;
    if (pc != null) await pc.dispose();
    _renderer.srcObject = null;
  }

  Future<void> _teardownHd() async {
    final player = _player;
    _player = null;
    _videoController = null;
    if (player != null) await player.dispose();
  }

  Future<void> _switchMode(String mode) async {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _error = null;
    });
    if (mode == 'live') {
      await _teardownHd();
      await _connect();
    } else {
      await _teardown();
      await _connectHd();
    }
  }

  Future<void> _connectHd() async {
    setState(() {
      _state = 'conectando';
      _error = null;
    });
    try {
      final descriptor = await widget.api
          .cameraStream(widget.camera['camera_id'].toString(), profile: 'main')
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      final hlsUrl = descriptor['hls_url'] as String?;
      if (hlsUrl == null || hlsUrl.isEmpty) {
        throw Exception('HLS no disponible para esta cámara.');
      }

      final player = Player();
      final controller = VideoController(player);
      _player = player;
      _videoController = controller;
      await player.open(Media(hlsUrl), play: true);
      if (!mounted) return;
      setState(() => _state = 'en vivo');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = 'error';
        _error = e.toString();
      });
    }
  }

  Future<void> _connect() async {
    setState(() {
      _state = 'conectando';
      _error = null;
    });
    await _teardown();
    try {
      final descriptor = await widget.api
          .cameraStream(widget.camera['camera_id'].toString())
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      final gatewayAvailable =
          descriptor['gateway_available'] as bool? ?? false;
      final webrtcUrl = descriptor['webrtc_url'] as String?;
      if (!gatewayAvailable || webrtcUrl == null) {
        throw Exception('El gateway de video no está disponible.');
      }

      final pc = await createPeerConnection({'iceServers': []});
      await pc.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );
      pc.onTrack = (event) {
        if (event.streams.isNotEmpty) _renderer.srcObject = event.streams.first;
      };
      pc.onConnectionState = (state) {
        if (!mounted) return;
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state ==
                RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          _onDisconnected();
        }
      };
      _pc = pc;

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      await _waitForIceGathering(pc);
      final local = await pc.getLocalDescription();
      if (local?.sdp == null) throw Exception('SDP local vacío.');

      final answer = await widget.api
          .webrtcAnswer(widget.camera['camera_id'].toString(), local!.sdp!)
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      await pc.setRemoteDescription(RTCSessionDescription(answer, 'answer'));
      setState(() => _state = 'en vivo');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = 'error';
        _error = e.toString();
      });
    }
  }

  Future<void> _waitForIceGathering(RTCPeerConnection pc) async {
    if (pc.iceGatheringState ==
        RTCIceGatheringState.RTCIceGatheringStateComplete) {
      return;
    }
    final completer = Completer<void>();
    pc.onIceGatheringState = (state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !completer.isCompleted) {
        completer.complete();
      }
    };
    try {
      await completer.future.timeout(const Duration(milliseconds: 1500));
    } catch (_) {}
  }

  void _onDisconnected() {
    if (_retrying) return;
    _retrying = true;
    setState(() => _state = 'reconectando');
    Future.delayed(const Duration(seconds: 3), () {
      _retrying = false;
      if (mounted) _connect();
    });
  }

  @override
  Widget build(BuildContext context) {
    final videoHd = _videoController;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.camera['name'].toString()),
        actions: [
          if (_state != 'error')
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(child: Text(_state.toUpperCase())),
            ),
        ],
      ),
      body: _state == 'error'
          ? MessageView(message: _error!, onRetry: _switchRetry)
          : Column(
              children: [
                Expanded(
                  child: Container(
                    color: Colors.black,
                    child: _mode == 'hd' && videoHd != null
                        ? Video(
                            controller: videoHd,
                            controls: NoVideoControls,
                            fit: BoxFit.contain,
                          )
                        : _renderer.renderVideo
                        ? RTCVideoView(
                            _renderer,
                            objectFit: RTCVideoViewObjectFit
                                .RTCVideoViewObjectFitContain,
                          )
                        : const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'live',
                        label: Text('En vivo'),
                        icon: Icon(Icons.sensors),
                      ),
                      ButtonSegment(
                        value: 'hd',
                        label: Text('HD'),
                        icon: Icon(Icons.high_quality),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (selection) =>
                        _switchMode(selection.first),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _mode == 'hd'
                        ? 'Canal ${widget.camera['channel']} · main 2K (H.265)'
                        : 'Canal ${widget.camera['channel']} · stream sub',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
    );
  }

  void _switchRetry() {
    if (_mode == 'hd') {
      _connectHd();
    } else {
      _connect();
    }
  }
}
