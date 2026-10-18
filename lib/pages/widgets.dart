import 'dart:io';

import 'package:flutter/material.dart';

class Poster extends StatelessWidget {
  final String url;

  /// 本地缓存的封面，有就优先用（没网也能显示）。
  final String? file;
  final double width;
  final double height;
  const Poster({super.key, required this.url, required this.width, required this.height, this.file});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: width,
      height: height,
      color: Colors.white10,
      child: const Icon(Icons.movie_outlined, color: Colors.white38),
    );
    final f = file == null ? null : File(file!);
    if (f != null && f.existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.file(f, width: width, height: height, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder),
      );
    }
    if (!url.startsWith('http')) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.network(
        url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
  }
}

extension WrapTap on Widget {
  Widget wrapTap(VoidCallback? onTap) => onTap == null ? this : InkWell(onTap: onTap, child: this);
}

/// 选集网格，详情页和播放页共用。
class EpisodeGrid extends StatelessWidget {
  final List<String> names;
  final int? current;
  final ValueChanged<int> onTap;
  const EpisodeGrid({super.key, required this.names, required this.onTap, this.current});

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 110,
        childAspectRatio: 2.4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      delegate: SliverChildBuilderDelegate(
        (_, i) {
          final selected = i == current;
          return OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              backgroundColor: selected ? Colors.blue : null,
              foregroundColor: selected ? Colors.white : null,
            ),
            onPressed: () => onTap(i),
            child: Text(names[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
          );
        },
        childCount: names.length,
      ),
    );
  }
}

/// 线路切换条。
class LineChips extends StatelessWidget {
  final List<String> names;
  final int current;
  final ValueChanged<int> onSelected;
  const LineChips({super.key, required this.names, required this.current, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (var i = 0; i < names.length; i++)
          ChoiceChip(label: Text(names[i]), selected: i == current, onSelected: (_) => onSelected(i)),
      ],
    );
  }
}
