import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DatasetSourcesPage extends StatefulWidget {
  const DatasetSourcesPage({super.key});

  @override
  State<DatasetSourcesPage> createState() => _DatasetSourcesPageState();
}

class _DatasetSourcesPageState extends State<DatasetSourcesPage> {
  late final Future<List<String>> _citations;

  @override
  void initState() {
    super.initState();
    _citations = rootBundle.loadString('assets/data/data_sources.json').then((contents) => List<String>.from(jsonDecode(contents) as List));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Dataset sources')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: FutureBuilder<List<String>>(
              future: _citations,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('Could not load dataset sources.'));
                }
                final citations = snapshot.data;
                if (citations == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('The following sources were used to build the Pokémon card dataset that powers card scanning and the catalog.', style: textTheme.bodyLarge),
                    const SizedBox(height: 24),
                    for (final citation in citations)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Card(
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: SelectableText(citation, style: textTheme.bodyLarge),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
