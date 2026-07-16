from functools import reduce
from hashlib import md5
import urllib.parse
import time
import requests
import json

# WBI签名相关常量
MIXIN_KEY_ENC_TAB = [
    46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49,
    33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13, 37, 48, 7, 16, 24, 55, 40,
    61, 26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11,
    36, 20, 34, 44, 52
]

# 用户Cookie - 请自行修改
COOKIE = 'buvid_fp_plain=undefined;fingerprint=f46c0b2cd386cb0414a92bbd77cf5f72;CURRENT_QUALITY=80;bp_t_offset_345721873=1216782810690355200;b_lsid=5FFA4723_19F0798D8E2;theme-tip-show=SHOWED;bmg_af_sc={"none":{"on":1,"def":"i0.hdslb.com"},"sgp":{"on":1,"def":"i0-sgp.hdslb.com"}};home_feed_column=5;LIVE_BUVID=AUTO1317558621919728;buvid4=F2ECF16F-33AF-A702-9AB9-BA038EC6742491245-024122309-86rQSrgSi3D+XQbtz2ZVr9CSsxDBpgiasEUDGu8wzUuuSBbHRE9awPCGA/XWRM6J;CURRENT_FNVAL=4048;header_theme_version=OPEN;buvid3=3961FE13-A856-6735-DED7-6DE69612916195474infoc;sid=8e9qsjqi;SESSDATA=78a6576a%2C1797944094%2Cb6e7e%2A62CjBYTvHpwKPg3Wd7n3i6LGTRJUAZMzHQVbUhXeNQmrjbnw6_HQgWVpy3apE0bUZJoIASVmRIMjRaTGt0T0F4Vy0yTmhEZWRtbVJwWHFFMTM5NkNnd01rVEVORzF0bmwxbWVZM2V0cWRXSDV6Vy1iVkJHZE9DV0J5YXJFNXhsY3VFelZxV0FISGNBIIEC;b_nut=1770861995;_uuid=38EB742A-1352-823E-5E97-556B51FBBEAF88472infoc;bili_jct=2bbbabbe3a832cf7cb0f197d91896672;bili_ticket=eyJhbGciOiJIUzI1NiIsImtpZCI6InMwMyIsInR5cCI6IkpXVCJ9.eyJleHAiOjE3ODI2MzU5MjUsImlhdCI6MTc4MjM3NjY2NSwicGx0IjotMX0.iGjI155fM0BD9npuKxPfjZxLNWYRlosSLo5TCN8KhC0;bili_ticket_expires=1782635865;bmg_af_switch=1;bmg_src_def_domain=i0.hdslb.com;browser_resolution=1699-828;buvid_fp=f46c0b2cd386cb0414a92bbd77cf5f72;DedeUserID=345721873;DedeUserID__ckMd5=82e8b18aa5a91af1;enable_web_push=DISABLE;hit-dyn-v2=1;PVID=2;rpdid=0zbfvShcDU|11srbgwKD|1H|3w1VQm6H;theme-switch-show=SHOWED;theme_style=light'

HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://www.bilibili.com/',
    'Cookie': COOKIE
}


def get_mixin_key(orig: str) -> str:
    """对 img_key 和 sub_key 进行字符顺序打乱编码"""
    return reduce(lambda s, i: s + orig[i], MIXIN_KEY_ENC_TAB, '')[:32]


def enc_wbi(params: dict, img_key: str, sub_key: str) -> dict:
    """为请求参数进行 wbi 签名"""
    mixin_key = get_mixin_key(img_key + sub_key)
    curr_time = round(time.time())
    params['wts'] = curr_time
    params = dict(sorted(params.items()))
    params = {
        k: ''.join(filter(lambda chr: chr not in "!'()*", str(v)))
        for k, v in params.items()
    }
    query = urllib.parse.urlencode(params)
    wbi_sign = md5((query + mixin_key).encode()).hexdigest()
    params['w_rid'] = wbi_sign
    return params


def get_wbi_keys() -> tuple:
    """获取最新的 img_key 和 sub_key"""
    resp = requests.get('https://api.bilibili.com/x/web-interface/nav', headers=HEADERS)
    resp.raise_for_status()
    json_content = resp.json()
    img_url: str = json_content['data']['wbi_img']['img_url']
    sub_url: str = json_content['data']['wbi_img']['sub_url']
    img_key = img_url.rsplit('/', 1)[1].split('.')[0]
    sub_key = sub_url.rsplit('/', 1)[1].split('.')[0]
    return img_key, sub_key


def search_article(keyword: str, page: int = 1, order: str = 'totalrank') -> dict:
    """
    搜索B站专栏文章
    
    Args:
        keyword: 搜索关键词
        page: 页码，默认第1页
        order: 排序方式
            - totalrank: 综合排序（默认）
            - click: 最多点击
            - pubdate: 最新发布
            - stow: 最多收藏
            - scores: 最多评论
            - attention: 最多喜欢
    
    Returns:
        搜索结果字典
    """
    img_key, sub_key = get_wbi_keys()
    
    params = {
        'search_type': 'article',
        'keyword': keyword,
        'page': page,
        'order': order
    }
    
    signed_params = enc_wbi(params, img_key, sub_key)
    
    url = 'https://api.bilibili.com/x/web-interface/wbi/search/type'
    resp = requests.get(url, params=signed_params, headers=HEADERS)
    resp.raise_for_status()
    return resp.json()


def format_article_result(article: dict) -> dict:
    """格式化单篇文章结果"""
    return {
        '标题': article.get('title', '').replace('<em class="keyword">', '').replace('</em>', ''),
        '作者': article.get('author', ''),
        '专栏ID': article.get('id', ''),
        '阅读量': article.get('view', 0),
        '评论数': article.get('review', 0),
        '收藏数': article.get('like', 0),
        '发布时间': time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(article.get('pubdate', 0))),
        '摘要': article.get('desc', '')[:100] + '...' if len(article.get('desc', '')) > 100 else article.get('desc', ''),
        '链接': f"https://www.bilibili.com/read/cv{article.get('id', '')}"
    }


def main():
    keyword = '绯月仙行录'
    
    print(f"搜索关键词: {keyword}")
    print(f"搜索类型: 专栏 (article)")
    print("-" * 50)
    
    try:
        result = search_article(keyword)
        
        if result.get('code') != 0:
            print(f"搜索失败: {result.get('message', '未知错误')}")
            return
        
        data = result.get('data', {})
        articles = data.get('result', [])
        
        print(f"共找到 {data.get('numResults', 0)} 条结果")
        print(f"当前第 {data.get('page', 1)} 页，共 {data.get('numPages', 1)} 页")
        print("-" * 50)
        
        if not articles:
            print("未找到相关专栏文章")
            return
        
        for i, article in enumerate(articles, 1):
            formatted = format_article_result(article)
            print(f"\n[{i}] {formatted['标题']}")
            print(f"    作者: {formatted['作者']}")
            print(f"    阅读: {formatted['阅读量']} | 评论: {formatted['评论数']} | 收藏: {formatted['收藏数']}")
            print(f"    发布: {formatted['发布时间']}")
            print(f"    摘要: {formatted['摘要']}")
            print(f"    链接: {formatted['链接']}")
        
        # 保存原始结果到JSON文件
        output_file = f"search_result_{keyword}.json"
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(result, f, ensure_ascii=False, indent=2)
        print(f"\n原始结果已保存到: {output_file}")
        
    except requests.exceptions.RequestException as e:
        print(f"请求错误: {e}")
    except Exception as e:
        print(f"发生错误: {e}")


if __name__ == '__main__':
    main()
