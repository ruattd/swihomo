import { readFileSync } from 'node:fs'
import { defineConfig } from 'vitepress'

const base = '/swihomo/'

const repo = 'https://github.com/ruattd/swihomo'
const repoRaw = 'https://raw.githubusercontent.com/ruattd/swihomo/main/'
const repoBlob = `${repo}/blob/main/`

const isAbsoluteUrl = (url: string) =>
  /^(?:[a-z][a-z\d+.-]*:|\/|#)/i.test(url)

// Pages rendered from the repository root README.md at build time. Both the
// English and the Simplified Chinese overview show the same source document.
const readmePages = new Set(['overview.md', 'zh/overview.md'])
const readmePath = new URL('../../README.md', import.meta.url)

const sharedThemeConfig = {
  logo: {
    light: '/logo-light.png',
    dark: '/logo-dark.png',
    alt: 'Swihomo',
  },

  socialLinks: [
    { icon: 'github', link: 'https://github.com/ruattd/swihomo' },
  ],
}

export default defineConfig({
  lang: 'en',
  title: 'Swihomo',
  description: 'Another mihomo client for iOS & macOS',
  base,
  srcDir: './pages',
  cleanUrls: true,

  head: [
    [
      'link',
      {
        rel: 'icon',
        type: 'image/png',
        href: `${base}logo-light.png`,
        media: '(prefers-color-scheme: light)',
      },
    ],
    [
      'link',
      {
        rel: 'icon',
        type: 'image/png',
        href: `${base}logo-dark.png`,
        media: '(prefers-color-scheme: dark)',
      },
    ],
    ['meta', { name: 'theme-color', content: '#ffffff', media: '(prefers-color-scheme: light)' }],
    ['meta', { name: 'theme-color', content: '#1b1b1f', media: '(prefers-color-scheme: dark)' }],
  ],

  locales: {
    root: {
      label: 'English',
      lang: 'en',
    },
    zh: {
      label: '简体中文',
      lang: 'zh-CN',
      title: 'Swihomo 文档',
      description: '面向 iOS 与 macOS 的 mihomo 客户端',
      themeConfig: {
        ...sharedThemeConfig,

        nav: [
          { text: '文档', link: '/zh/getting-started' },
          { text: '隐私政策', link: '/zh/privacy-policy' },
        ],

        sidebar: [
          {
            text: '快速开始',
            link: '/zh/getting-started',
            items: [{ text: '概览', link: '/zh/overview' }],
          },
          {
            text: '用户指南',
            items: [
              { text: '配置与订阅', link: '/zh/profiles' },
              { text: '设置', link: '/zh/settings' },
              { text: '状态与故障排查', link: '/zh/troubleshooting' },
            ],
          },
          {
            text: '架构',
            items: [
              { text: '内嵌 Mihomo Bridge', link: '/zh/mihomo-bridge' },
            ],
          },
        ],

        outline: {
          level: [2, 3],
          label: '本页内容',
        },

        search: {
          provider: 'local',
          options: {
            translations: {
              button: {
                buttonText: '搜索',
                buttonAriaLabel: '搜索',
              },
              modal: {
                displayDetails: '显示详细列表',
                resetButtonTitle: '清除查询条件',
                backButtonTitle: '返回',
                noResultsText: '没有找到结果',
                footer: {
                  selectText: '选择',
                  selectKeyAriaLabel: '回车',
                  navigateText: '切换',
                  navigateUpKeyAriaLabel: '向上',
                  navigateDownKeyAriaLabel: '向下',
                  closeText: '关闭',
                  closeKeyAriaLabel: 'Escape',
                },
              },
            },
          },
        },

        darkModeSwitchLabel: '外观',
        lightModeSwitchTitle: '切换到浅色主题',
        darkModeSwitchTitle: '切换到深色主题',
        sidebarMenuLabel: '菜单',
        returnToTopLabel: '返回顶部',
        langMenuLabel: '切换语言',
        skipToContentLabel: '跳转到内容',

        docFooter: {
          prev: '上一页',
          next: '下一页',
        },

        footer: {
          message: '基于 <a href="https://github.com/ruattd/swihomo/blob/main/LICENSE">AGPL-3.0</a> 许可证发布。',
          copyright: '版权所有 © 2026 ruattd',
        },
      },
    },
  },

  themeConfig: {
    ...sharedThemeConfig,

    nav: [
      { text: 'Docs', link: '/getting-started' },
      { text: 'Privacy', link: '/privacy-policy' },
    ],

    sidebar: [
      {
        text: 'Getting Started',
        link: '/getting-started',
        items: [{ text: 'Overview', link: '/overview' }],
      },
      {
        text: 'User Guide',
        items: [
          { text: 'Profiles & Subscriptions', link: '/profiles' },
          { text: 'Settings', link: '/settings' },
          { text: 'Status & Troubleshooting', link: '/troubleshooting' },
        ],
      },
      {
        text: 'Architecture',
        items: [
          { text: 'Embedded Mihomo Bridge', link: '/mihomo-bridge' },
        ],
      },
    ],

    outline: {
      level: [2, 3],
      label: 'On this page',
    },

    search: {
      provider: 'local',
    },

    footer: {
      message: 'Released under the <a href="https://github.com/ruattd/swihomo/blob/main/LICENSE">AGPL-3.0</a> license.',
      copyright: 'Copyright © 2026 ruattd',
    },
  },

  // The overview page body is read from the repository root README.md at render time.
  // Its repo-relative asset and license links resolve against the repository rather
  // than the docs source tree.
  markdown: {
    config(md) {
      const parse = md.parse.bind(md)

      md.parse = (src, env) => {
        if (readmePages.has(env?.relativePath)) {
          src = readFileSync(readmePath, 'utf-8')
        }
        return parse(src, env)
      }

      md.core.ruler.push('readme-repo-links', (state) => {
        if (!readmePages.has(state.env.relativePath)) return

        const raw = (url: string) =>
          isAbsoluteUrl(url) ? url : repoRaw + url.replace(/^\.\//, '')
        const blob = (url: string) =>
          isAbsoluteUrl(url) ? url : repoBlob + url.replace(/^\.\//, '')
        const rewriteSrcset = (value: string) =>
          value
            .split(',')
            .map((candidate) => {
              const [url, ...descriptor] = candidate.trim().split(/\s+/)
              return [raw(url), ...descriptor].join(' ')
            })
            .join(', ')

        const rewriteTokens = (tokens: typeof state.tokens) => {
          for (const token of tokens) {
            if (token.type === 'html_block' || token.type === 'html_inline') {
              token.content = token.content
                .replace(
                  /\bsrcset="([^"]*)"/g,
                  (_, value: string) => `srcset="${rewriteSrcset(value)}"`,
                )
                .replace(/\bsrc="([^"]*)"/g, (_, url: string) => `src="${raw(url)}"`)
                .replace(/\bhref="([^"]*)"/g, (_, url: string) => `href="${blob(url)}"`)
            } else if (token.type === 'link_open') {
              const hrefIndex = token.attrIndex('href')
              if (hrefIndex >= 0) {
                token.attrs![hrefIndex][1] = blob(token.attrs![hrefIndex][1])
              }
            } else if (token.type === 'image') {
              const srcIndex = token.attrIndex('src')
              if (srcIndex >= 0) {
                token.attrs![srcIndex][1] = raw(token.attrs![srcIndex][1])
              }
            }
            if (token.children) rewriteTokens(token.children)
          }
        }

        rewriteTokens(state.tokens)
      })
    },
  },
})
