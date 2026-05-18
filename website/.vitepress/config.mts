import { defineConfig } from 'vitepress'

// 项目部署到 https://classflow-api.github.io/cc-anywhere/，所以 base 是 /cc-anywhere/
// 若后续绑定自有域名（如 cc-anywhere.classflow.dev），把 base 改回 '/'
const REPO = 'classflow-api/cc-anywhere'
const SITE = `https://github.com/${REPO}`

export default defineConfig({
  base: '/cc-anywhere/',
  lang: 'zh-CN',
  title: '遥指 · cc-anywhere',
  titleTemplate: ':title | 遥指',
  description:
    '跨端 Claude Code 协作客户端 — Mac 跑长任务，手机随时接管。Cross-device companion for Claude Code.',
  lastUpdated: true,
  cleanUrls: true,
  metaChunk: true,

  // 部分页面从 docs/CONTRIBUTING.md 等仓库内文档复制过来，含指向 GitHub repo
  // 内 .github / LICENSE 等仓库相对路径 — VitePress 检测为 dead link，忽略。
  // 站内文档的 dead link 还是会报。
  ignoreDeadLinks: [
    /^\.\/\.github\//,
    /^\.\/docs\//,
    /^\.\/LICENSE/,
    /^\.\/CHANGELOG\.md/,
    /^\.\/CODE_OF_CONDUCT\.md/,
    /^\.\/SECURITY\.md/,
  ],

  head: [
    ['link', { rel: 'icon', href: '/cc-anywhere/favicon.svg', type: 'image/svg+xml' }],
    ['meta', { name: 'theme-color', content: '#59CFE7' }],
    ['meta', { property: 'og:type', content: 'website' }],
    ['meta', { property: 'og:title', content: '遥指 · cc-anywhere' }],
    ['meta', { property: 'og:description', content: 'Mac 跑长任务，手机随时接管 — 基于 Claude Code Hook 实时桥接的跨端协作客户端' }],
    ['meta', { property: 'og:url', content: `https://${REPO.split('/')[0]}.github.io/cc-anywhere/` }],
  ],

  themeConfig: {
    logo: { src: '/logo.svg', width: 24, height: 24 },
    siteTitle: '遥指 · cc-anywhere',

    nav: [
      { text: '首页', link: '/' },
      {
        text: '指南',
        items: [
          { text: '介绍', link: '/guide/introduction' },
          { text: '快速开始', link: '/guide/quick-start' },
          { text: '完整安装', link: '/guide/installation' },
          { text: '架构', link: '/guide/architecture' },
          { text: '常见问题', link: '/guide/faq' },
          { text: '贡献指南', link: '/guide/contributing' },
        ],
      },
      { text: 'English', link: `${SITE}/blob/master/README.en.md`, target: '_blank' },
      { text: 'Changelog', link: `${SITE}/blob/master/CHANGELOG.md`, target: '_blank' },
      { text: `v0.1.0`, link: `${SITE}/releases`, target: '_blank' },
    ],

    sidebar: {
      '/guide/': [
        {
          text: '开始',
          items: [
            { text: '介绍', link: '/guide/introduction' },
            { text: '快速开始', link: '/guide/quick-start' },
          ],
        },
        {
          text: '部署',
          items: [
            { text: '完整安装', link: '/guide/installation' },
          ],
        },
        {
          text: '深入',
          items: [
            { text: '架构', link: '/guide/architecture' },
            { text: '常见问题', link: '/guide/faq' },
            { text: '贡献指南', link: '/guide/contributing' },
          ],
        },
      ],
    },

    socialLinks: [{ icon: 'github', link: SITE }],

    editLink: {
      pattern: `${SITE}/edit/master/website/:path`,
      text: '在 GitHub 上编辑此页',
    },

    docFooter: {
      prev: '上一篇',
      next: '下一篇',
    },

    footer: {
      message: '基于 MIT 协议发布',
      copyright:
        'Copyright © 2026 Beijing Yoolines Interactive Information Technology Co., Ltd. (北京友联互动信息技术有限公司)',
    },

    outline: { label: '本页目录', level: [2, 3] },
    returnToTopLabel: '回到顶部',
    sidebarMenuLabel: '菜单',
    darkModeSwitchLabel: '主题',
    lightModeSwitchTitle: '切换到浅色模式',
    darkModeSwitchTitle: '切换到深色模式',

    search: {
      provider: 'local',
      options: {
        translations: {
          button: { buttonText: '搜索', buttonAriaLabel: '搜索' },
          modal: {
            displayDetails: '显示详细信息',
            resetButtonTitle: '清空',
            backButtonTitle: '返回',
            noResultsText: '无结果',
            footer: { selectText: '选择', navigateText: '切换', closeText: '关闭' },
          },
        },
      },
    },
  },
})
