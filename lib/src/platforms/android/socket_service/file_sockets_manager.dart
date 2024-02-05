part of 'nearby_socket_service.dart';

class FileSocketsManager {
  FileSocketsManager(this._network, this._service, this._pingManager);

  final NearbyServiceNetwork _network;
  final NearbyAndroidService _service;
  final NearbySocketPingManager _pingManager;

  final _filesSockets = <String, FilesSocket>{};
  final _serverWaitingRequests = <String, HttpRequest>{};

  NearbyServiceFilesListener? _filesListener;
  NearbyDeviceInfo? _sender;
  NearbyMessageFilesRequest? _cachedFilesRequest;
  Future? _socketCreationFuture;
  var _connectionData = const NearbyAndroidCommunicationChannelData();

  void setListener(NearbyServiceFilesListener? listener) {
    _filesListener = listener;
  }

  void setConnectionData(NearbyAndroidCommunicationChannelData? data) {
    _connectionData = data ?? _connectionData;
  }

  void onWsRequest(HttpRequest request) {
    final type = NearbySocketType.fromRequest(request);
    final filesPackId = NearbyFilesPackId.fromRequest(request);
    if (type == NearbySocketType.file && filesPackId != null) {
      Logger.debug('Save a connection request $filesPackId from client');
      _serverWaitingRequests[filesPackId] = request;
    }
  }

  Future<void> handleFileMessageContent(
    NearbyMessageFilesContent content, {
    required NearbyDeviceInfo? sender,
    required bool isReceived,
  }) async {
    if (sender != null) {
      _sender = sender;
      Logger.debug('Sender was set to $_sender');
    }
    final socketExists = _filesSockets[content.id] != null;

    final isRequest = content is NearbyMessageFilesRequest;

    final isPositiveResponse =
        content is NearbyMessageFilesResponse && content.response;

    if (isRequest) {
      _cachedFilesRequest = content;
      Logger.debug('Files pack request ${content.id} was cached');
    }
    if (!socketExists) {
      final info = await _service.getConnectionInfo();
      if (info != null && info.groupFormed) {
        if (info.isGroupOwner) {
          if (isPositiveResponse && _cachedFilesRequest != null) {
            _socketCreationFuture = _startFilesServerSocket(
              _cachedFilesRequest!,
            );
          }
        } else {
          NearbyMessageFilesRequest? request;

          if (!isReceived &&
              isPositiveResponse &&
              _cachedFilesRequest != null) {
            request = _cachedFilesRequest!;
          } else if (isRequest) {
            request = content;
          }

          if (request != null) {
            _socketCreationFuture = _connectToFilesSocket(
              request,
              ownerIpAddress: info.ownerIpAddress,
            );
          }
        }
      }
    }

    if (isReceived && isPositiveResponse && _cachedFilesRequest != null) {
      await _socketCreationFuture?.whenComplete(
        () async {
          await _startDataTransfer(_cachedFilesRequest!);
          _socketCreationFuture = null;
          _cachedFilesRequest = null;
        },
      );
    }
  }

  Future<void> closeAll() async {
    for (final fileSocket in _filesSockets.values) {
      await fileSocket.close();
    }
    _filesSockets.clear();
    _filesListener = null;
    _cachedFilesRequest = null;
    _socketCreationFuture = null;
  }

  Future<void> _connectToFilesSocket(
    NearbyMessageFilesRequest filesRequest, {
    required String ownerIpAddress,
  }) async {
    try {
      final response = await _network.pingServer(
        address: ownerIpAddress,
        port: _connectionData.port,
      );
      if (await _pingManager.checkPong(response)) {
        await _startFilesSocket(
          filesRequest,
          onCreateSocket: () => _network.connectToSocket(
            ownerIpAddress: ownerIpAddress,
            port: _connectionData.port,
            socketType: NearbySocketType.file,
            headers: {
              NearbyFilesPackId.key: filesRequest.id,
            },
          ),
        );
      } else {
        Logger.debug(
          'Files server is unavailable, reconnect in ${_connectionData.clientReconnectInterval}s',
        );
        await Future.delayed(
          _connectionData.clientReconnectInterval,
          () => _connectToFilesSocket(
            filesRequest,
            ownerIpAddress: ownerIpAddress,
          ),
        );
      }
    } catch (e) {
      Logger.error(e);
    }
  }

  Future<void> _startFilesServerSocket(
    NearbyMessageFilesRequest filesRequest,
  ) async {
    final connectionRequest = _serverWaitingRequests[filesRequest.id];

    if (connectionRequest != null) {
      Logger.debug('Found cached server files request ${filesRequest.id}');

      final result = await _startFilesSocket(
        filesRequest,
        onCreateSocket: () => WebSocketTransformer.upgrade(connectionRequest),
      );
      if (result) {
        _serverWaitingRequests.remove(filesRequest.id);
      }
    }
  }

  Future<bool> _startFilesSocket(
    NearbyMessageFilesRequest filesRequest, {
    required Future<WebSocket?> Function() onCreateSocket,
  }) async {
    final socket = await onCreateSocket();
    if (socket != null && _sender != null) {
      _filesSockets[filesRequest.id] = FilesSocket.startListening(
        sender: _sender!,
        filesRequest: filesRequest,
        socket: socket,
        listener: _filesListener,
        onDestroy: _filesSockets.remove,
      );
      Logger.info('Created a socket for the files pack ${filesRequest.id}');
      return true;
    }
    return false;
  }

  Future<void> _startDataTransfer(NearbyMessageFilesRequest request) async {
    final filesSocket = _filesSockets[request.id];
    if (filesSocket != null) {
      Logger.debug('Start transferring the files pack ${request.id}');
      for (var i = 0; i < request.files.length; i++) {
        try {
          final fileInfo = request.files[i];
          await _streamFile(
            request.id,
            filesSocket: filesSocket,
            file: File(fileInfo.path),
          )?.asFuture();

          filesSocket.sendData(FilesSocket.separateCommandOf(i));
          Logger.debug('Sent separate command for file №$i');
        } catch (e) {
          Logger.error(e);
          continue;
        }
      }
      filesSocket.sendData(FilesSocket.finishCommand);
      Logger.debug('Sent finish command for the pack ${request.id}');
    }
  }

  StreamSubscription? _streamFile(
    String id, {
    required FilesSocket filesSocket,
    required File file,
  }) {
    return file.openRead().listen(filesSocket.sendData);
  }
}
