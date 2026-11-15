import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/scrape_review_item.dart';

/// 本次运行内保留候选，关闭表单或切换页面后可继续确认。
final scrapeReviewItemsProvider =
    StateProvider<List<ScrapeReviewItem>>((ref) => []);
