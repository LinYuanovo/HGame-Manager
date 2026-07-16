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
COOKIE = 'buvid_fp_plain=undefined;fingerprint=f46c0b2cd386cb0414a92bbd77cf5f72;CURRENT_QUALITY=80;bp_t_offset_345721873=1216782810690355200;b_lsid=F1DE1BDD_19F07B3FADC;theme-tip-show=SHOWED;bmg_af_sc={"none":{"on":1,"def":"i0.hdslb.com"},"sgp":{"on":1,"def":"i0-sgp.hdslb.com"}};home_feed_column=5;LIVE_BUVID=AUTO1317558621919728;buvid4=F2ECF16F-33AF-A702-9AB9-BA038EC6742491245-024122309-86rQSrgSi3D+XQbtz2ZVr9CSsxDBpgiasEUDGu8wzUuuSBbHRE9awPCGA/XWRM6J;CURRENT_FNVAL=4048;header_theme_version=OPEN;buvid3=3961FE13-A856-6735-DED7-6DE69612916195474infoc;sid=8e9qsjqi;SESSDATA=78a6576a%2C1797944094%2Cb6e7e%2A62CjBYTvHpwKPg3Wd7n3i6LGTRJUAZMzHQVbUhXeNQmrjbnw6_HQgWVpy3apE0bUZJoIASVmRIMjRaTGt0T0F4Vy0yTmhEZWRtbVJwWHFFMTM5NkNnd01rVEVORzF0bmwxbWVZM2V0cWRXSDV6Vy1iVkJHZE9DV0J5YXJFNXhsY3VFelZxV0FISGNBIIEC;b_nut=1770861995;_uuid=38EB742A-1352-823E-5E97-556B51FBBEAF88472infoc;bili_jct=2bbbabbe3a832cf7cb0f197d91896672;bili_ticket=eyJhbGciOiJIUzI1NiIsImtpZCI6InMwMyIsInR5cCI6IkpXVCJ9.eyJleHAiOjE3ODI2MzU5MjUsImlhdCI6MTc4MjM3NjY2NSwicGx0IjotMX0.iGjI155fM0BD9npuKxPfjZxLNWYRlosSLo5TCN8KhC0;bili_ticket_expires=1782635865;bmg_af_switch=1;bmg_src_def_domain=i0.hdslb.com;browser_resolution=1699-828;buvid_fp=f46c0b2cd386cb0414a92bbd77cf5f72;DedeUserID=345721873;DedeUserID__ckMd5=82e8b18aa5a91af1;enable_web_push=DISABLE;hit-dyn-v2=1;PVID=2;rpdid=0zbfvShcDU|11srbgwKD|1H|3w1VQm6H;theme-switch-show=SHOWED;theme_style=light'

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


def get_article_view(article_id: int) -> dict:
    """
    获取B站专栏文章详情
    
    Args:
        article_id: 专栏文章ID (cv号，不带cv前缀)
    
    Returns:
        文章详情字典
    """
    img_key, sub_key = get_wbi_keys()
    
    params = {
        'id': article_id,
        'gaia_source': 'main_web'
    }
    
    signed_params = enc_wbi(params, img_key, sub_key)
    
    url = 'https://api.bilibili.com/x/article/view'
    resp = requests.get(url, params=signed_params, headers=HEADERS)
    resp.raise_for_status()
    return resp.json()


def format_time(timestamp: int) -> str:
    """将时间戳格式化为可读时间"""
    if timestamp:
        return time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(timestamp))
    return '未知'


def print_article_info(data: dict) -> None:
    """打印文章基本信息"""
    print("=" * 60)
    print(f"标题: {data.get('title', '未知')}")
    print(f"专栏ID: cv{data.get('id', '')}")
    print("=" * 60)
    
    summary = data.get('summary', '')
    if summary:
        print(f"\n摘要: {summary[:200]}...")
    
    print(f"\n链接: https://www.bilibili.com/read/cv{data.get('id', '')}")


def get_article_content(data: dict) -> str:
    """
    提取文章正文内容（纯文本）
    
    Args:
        data: API返回的data对象
    
    Returns:
        文章正文纯文本
    """
    content = data.get('content', '')
    content_type = data.get('type', 0)
    
    if content_type == 0:
        # HTML格式，简单去除标签
        import re
        text = re.sub(r'<[^>]+>', '\n', content)
        text = re.sub(r'\n{3,}', '\n\n', text)
        return text.strip()
    elif content_type == 3:
        # JSON格式
        try:
            json_content = json.loads(content) if isinstance(content, str) else content
            ops = json_content.get('ops', [])
            text_parts = []
            for op in ops:
                insert = op.get('insert', '')
                if isinstance(insert, str):
                    text_parts.append(insert)
                elif isinstance(insert, dict):
                    if 'native-image' in insert:
                        img_info = insert['native-image']
                        text_parts.append(f"[图片: {img_info.get('alt', '')}]")
                    elif 'video-card' in insert:
                        text_parts.append(f"[视频: {insert['video-card'].get('id', '')}]")
                    elif 'article-card' in insert:
                        text_parts.append(f"[专栏: {insert['article-card'].get('id', '')}]")
            return ''.join(text_parts)
        except:
            return content
    return content


def main():
    import sys
    
    if len(sys.argv) < 2:
        print("用法: python bili_article_view.py <article_id>")
        print("示例: python bili_article_view.py 1")
        print("      python bili_article_view.py 41358718")
        return
    
    try:
        article_id = int(sys.argv[1])
    except ValueError:
        print("错误: 文章ID必须是数字")
        return
    
    print(f"正在获取专栏文章 cv{article_id} ...")
    
    try:
        result = get_article_view(article_id)
        
        if result.get('code') != 0:
            code = result.get('code')
            message = result.get('message', '未知错误')
            if code == -404:
                print(f"错误: 文章不存在 (cv{article_id})")
            elif code == -352:
                print(f"错误: 请求被风控，请检查Cookie设置")
            elif code == -400:
                print(f"错误: 请求错误 - {message}")
            else:
                print(f"错误 [{code}]: {message}")
            return
        
        data = result.get('data', {})
        print_article_info(data)
        
        # 保存原始结果到JSON文件
        output_file = f"article_cv{article_id}.json"
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(result, f, ensure_ascii=False, indent=2)
        print(f"\n原始结果已保存到: {output_file}")
        
        # 显示正文预览
        content = get_article_content(data)
        if content:
            print("\n" + "=" * 60)
            print("正文预览 (前500字):")
            print("=" * 60)
            print(content[:500])
            if len(content) > 500:
                print("...")
        
    except requests.exceptions.RequestException as e:
        print(f"请求错误: {e}")
    except Exception as e:
        print(f"发生错误: {e}")


if __name__ == '__main__':
    main()
