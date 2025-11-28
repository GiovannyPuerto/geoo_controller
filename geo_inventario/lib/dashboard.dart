import 'dart:convert';
import 'dart:io' as io;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geo_inventario/platform_file_picker.dart';
import 'package:geo_inventario/services/api_service.dart';
import 'package:geo_inventario/tabs/analysis_tab.dart';
import 'package:geo_inventario/tabs/movements_tab.dart';
import 'package:geo_inventario/tabs/summary_tab.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:universal_html/html.dart' as html;

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ApiService _apiService = ApiService();

  String? lastUpdateTime;
  bool hasBaseData = false; // This might need to be managed globally or passed

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadLastUpdateTime();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadLastUpdateTime() async {
    try {
      final data = await _apiService.getLastUpdateTime();
      if (mounted) {
        setState(() {
          if (data != null && data != 'Error') {
            final dateTime = DateTime.parse(data);
            lastUpdateTime =
                DateFormat('dd/MM/yyyy HH:mm').format(dateTime.toLocal());
          } else {
            lastUpdateTime = 'No se ha actualizado';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          lastUpdateTime = 'Error';
        });
      }
    }
  }

  Future<void> _pickAndUploadFile() async {
    final localContext = context;
    try {
      FilePickerResult? result = await getPlatformFilePicker().pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (result != null) {
        PlatformFile platformFile = result.files.single;
        await _uploadBaseFile(platformFile);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(localContext).showSnackBar(
          SnackBar(
            content: Text('Error al seleccionar el archivo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _uploadBaseFile(PlatformFile platformFile) async {
    final localContext = context;
    if (!mounted) return;

    // Check if file bytes are available
    if (platformFile.bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(localContext).showSnackBar(
          const SnackBar(
            content: Text('Error: No se pudieron leer los bytes del archivo'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Cargando archivo base...'),
            ],
          ),
        );
      },
    );

    try {
      var responseData = await _apiService.uploadBaseFile(
        platformFile.bytes!.toList(),
        platformFile.name,
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading dialog

      if (responseData['ok'] == true) {
        setState(() {
          hasBaseData = true;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                responseData['message'] ?? 'Archivo cargado exitosamente',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
        // Reload all data by re-initializing the dashboard page or triggering a reload in tabs
        // For simplicity, we can just reload the update time
        _loadLastUpdateTime();
        // A better approach would be to have a global state management to notify tabs
      } else {
        if (mounted) {
          ScaffoldMessenger.of(localContext).showSnackBar(
            SnackBar(
              content: Text(
                responseData['error'] ?? 'Error al cargar el archivo',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(localContext).pop();
      if (mounted) {
        ScaffoldMessenger.of(localContext).showSnackBar(
          SnackBar(
            content: Text('Error de conexión: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _uploadUpdateFile() async {
    final localContext = context;
    try {
      FilePickerResult? result = await getPlatformFilePicker().pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        allowMultiple: true,
      );

      if (result == null || result.files.isEmpty) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Procesando archivo(s) de actualización...'),
              ],
            ),
          );
        },
      );

      try {
        final filesBytes = <List<int>>[];
        final fileNames = <String>[];

        for (var file in result.files) {
          List<int> bytes;
          if (file.bytes != null && file.bytes!.isNotEmpty) {
            bytes = file.bytes!.toList();
          } else if (file.path != null) {
            // For desktop platforms, read from file path
            final ioFile = io.File(file.path!);
            bytes = await ioFile.readAsBytes();
          } else {
            if (mounted) {
              Navigator.of(localContext).pop(); // Close loading dialog
              ScaffoldMessenger.of(localContext).showSnackBar(
                SnackBar(
                  content: Text(
                      'Error: No se pudieron leer los bytes del archivo ${file.name}'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            return;
          }
          filesBytes.add(bytes);
          fileNames.add(file.name);
        }

        var responseData =
            await _apiService.uploadUpdateFiles(filesBytes, fileNames);

        if (!mounted) return;
        Navigator.of(context).pop(); // Close loading dialog

        // Try to parse response
        try {
          var jsonResponse = json.decode(responseData['body']);
          if (jsonResponse['ok'] == true) {
            ScaffoldMessenger.of(localContext).showSnackBar(
              SnackBar(
                content: Text(jsonResponse['message'] ??
                    'Archivos de actualización procesados exitosamente.'),
                backgroundColor: Colors.green,
              ),
            );
            _loadLastUpdateTime(); // Reload data
          } else {
            ScaffoldMessenger.of(localContext).showSnackBar(
              SnackBar(
                content:
                    Text(jsonResponse['error'] ?? 'Error al procesar archivos'),
                backgroundColor: Colors.red,
              ),
            );
          }
        } catch (parseError) {
          // If response is not JSON, show raw response
          ScaffoldMessenger.of(localContext).showSnackBar(
            SnackBar(
              content: Text('Respuesta del servidor: ${responseData['body']}'),
              backgroundColor:
                  responseData['statusCode'] == 200 ? Colors.green : Colors.red,
            ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        Navigator.of(localContext).pop(); // Close loading dialog
        ScaffoldMessenger.of(localContext).showSnackBar(
          SnackBar(
            content: Text('Error de conexión: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      // Error picking file
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al seleccionar archivos: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'statics/images/logo_geoflora.png',
              height: 40,
            ),
            const SizedBox(width: 10),
            const Text('Dashboard de Inventario'),
            const Spacer(),
            if (lastUpdateTime != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Última actualización: $lastUpdateTime',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black,
                  ),
                ),
              ),
          ],
        ),
        backgroundColor: const Color(0xFF10B981),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_sharp),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.cloud_upload_outlined, color: Colors.white),
            onSelected: (value) {
              if (value == 'base') {
                _pickAndUploadFile();
              } else if (value == 'update') {
                _uploadUpdateFile();
              }
            },
            itemBuilder: (BuildContext context) => [
              if (!hasBaseData)
                const PopupMenuItem(
                  value: 'base',
                  child: Text('Cargar archivo base'),
                ),
              const PopupMenuItem(
                value: 'update',
                child: Text('Cargar archivo de actualización'),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Resumen General'),
            Tab(text: 'Análisis de Productos'),
            Tab(text: 'Movimientos'),
          ],
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: <Widget>[
          SummaryTabPage(onPickFile: _pickAndUploadFile),
          const AnalysisTabPage(),
          const MovementsTabPage(),
        ],
      ),
    );
  }
}
