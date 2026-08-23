import { defineConfig } from 'vitepress'

// https://vitepress.dev/reference/site-config
export default defineConfig({
  // GitHub Pages 部署在仓库子路径下，必须与仓库名一致
  base: '/HGame-Manager/',
  lang: 'zh-CN',
  title: '黄油仓库',
  description: '基于 Flutter 开发的 Windows 本地 HGame 管理器 —— 使用文档与图文教程',
  cleanUrls: true,
  lastUpdated: true,
  // 排除目录中已有的非文档站文件
  srcExclude: ['dark-theme-preview.html', 'superpowers/**'],

  head: [
    ['link', { rel: 'icon', type: 'image/png', href: '/HGame-Manager/logo.png' }],
    ['meta', { name: 'theme-color', content: '#2563EB' }],
  ],

  themeConfig: {
    logo: '/logo.png',
    siteTitle: '黄油仓库',

    nav: [
      { text: '首页', link: '/' },
      { text: '使用指南', link: '/guide/getting-started', activeMatch: '/guide/' },
      { text: '常见问题', link: '/faq' },
      { text: '参与开发', link: '/development/build', activeMatch: '/development/' },
      {
        text: 'v1.4.8',
        items: [
          { text: '更新日志', link: 'https://github.com/LinYuanovo/HGame-Manager/blob/master/CHANGELOG.md' },
          { text: '下载最新版', link: 'https://github.com/LinYuanovo/HGame-Manager/releases' },
        ],
      },
    ],

    sidebar: {
      '/guide/': [
        {
          text: '快速上手',
          items: [
            { text: '下载与安装', link: '/guide/getting-started' },
            { text: '添加游戏（多种方式）', link: '/guide/add-games' },
          ],
        },
        {
          text: '核心功能',
          items: [
            { text: '检查游戏更新', link: '/guide/check-update' },
            { text: '分类管理', link: '/guide/categories' },
            { text: '存档管理', link: '/guide/saves' },
            { text: '攻略管理', link: '/guide/guide' },
            { text: '导入工具与转区启动', link: '/guide/tools' },
            { text: '自定义管理', link: '/guide/customize' },
            { text: '软件更新', link: '/guide/update-app' },
            { text: 'WebDav', link: '/guide/webdav' },
          ],
        },
      ],
      '/development/': [
        {
          text: '参与开发',
          items: [{ text: '从源码构建', link: '/development/build' }],
        },
      ],
    },

    socialLinks: [
      { icon: 'github', link: 'https://github.com/LinYuanovo/HGame-Manager' },
    ],

    search: {
      provider: 'local',
    },

    editLink: {
      pattern: 'https://github.com/LinYuanovo/HGame-Manager/edit/master/docs/:path',
      text: '在 GitHub 上编辑此页',
    },

    footer: {
      message: '基于 AGPL-3.0 许可发布',
      copyright: 'Copyright © LinYuanovo',
    },

    // 中文界面文案
    outline: { label: '本页目录' },
    docFooter: { prev: '上一页', next: '下一页' },
    lastUpdatedText: '最后更新',
    returnToTopLabel: '回到顶部',
    sidebarMenuLabel: '菜单',
    darkModeSwitchLabel: '外观',
    lightModeSwitchTitle: '切换到浅色模式',
    darkModeSwitchTitle: '切换到深色模式',
    notFound: {
      title: '页面不存在',
      quote: '你要找的页面可能已被移动或删除。',
      linkLabel: '返回首页',
      linkText: '返回首页',
    },
  },
})
