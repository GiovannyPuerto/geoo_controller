import 'package:flutter/material.dart';
import 'package:data_table_2/data_table_2.dart';

class PreviewPage extends StatelessWidget {
  final List<List<dynamic>> data;
  final String filePath;

  const PreviewPage({super.key, required this.data, required this.filePath});

  @override
  Widget build(BuildContext context) {
    // Define green and yellow columns based on user's description
    const greenColumns = ['LOCALIZACION', 'CATEGORIA', 'CODIGO', 'DESCRIPCION', 'FECHA', 'ENTRADA', 'SALIDA', 'UNITARIO', 'TOTAL', 'LOTE/UBIC'];
    const yellowColumns = ['ORIGEN/DES', 'PROYECT', 'DESC_LI', 'LINE'];

    final headers = data.isNotEmpty ? data[0] : [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Previsualización del Archivo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            onPressed: () {
              // TODO: Implement the actual upload
              Navigator.pop(context, true); // Return true to indicate upload confirmation
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    'Mostrando las primeras 50 filas de: ${filePath.split('/').last}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: DataTable2(
              columnSpacing: 12,
              horizontalMargin: 12,
              minWidth: 800,
              columns: [
                for (var i = 0; i < headers.length; i++)
                  DataColumn2(
                    label: Container(
                      color: greenColumns.contains(headers[i])
                          ? Colors.green.withOpacity(0.3)
                          : yellowColumns.contains(headers[i])
                              ? Colors.yellow.withOpacity(0.3)
                              : Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(headers[i].toString()),
                    ),
                  ),
              ],
              rows: data.skip(1).take(50).map((row) {
                return DataRow(
                  cells: row.map((cell) {
                    return DataCell(Text(cell.toString()));
                  }).toList(),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
