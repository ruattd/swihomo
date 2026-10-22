import { defineConfig } from 'vitepress'

const base = '/swihomo/'

export default defineConfig({
  lang: 'en',
  title: 'Swihomo',
  description: 'Another mihomo client for iOS & macOS',
  base,
  cleanUrls: false,

  head: [
    ['link', { rel: 'icon', type: 'image/svg+xml', href: `${base}favicon.svg` }],
    ['meta', { name: 'theme-color', content: '#ffffff', media: '(prefers-color-scheme: light)' }],
    ['meta', { name: 'theme-color', content: '#1b1b1f', media: '(prefers-color-scheme: dark)' }],
  ],

  themeConfig: {
    logo: '/favicon.svg',

    nav: [
      { text: 'Architecture', link: '/pages/architecture/mihomo-bridge/' },
      { text: 'Privacy', link: '/privacy-policy/' },
    ],

    sidebar: {
      '/pages/': [
        {
          text: 'Architecture',
          items: [
            { text: 'Embedded Mihomo Bridge', link: '/pages/architecture/mihomo-bridge/' },
          ],
        },
      ],
      '/privacy-policy/': [
        {
          text: 'Legal',
          items: [{ text: 'Privacy Policy', link: '/privacy-policy/' }],
        },
      ],
    },

    outline: {
      level: [2, 3],
      label: 'On this page',
    },

    search: {
      provider: 'local',
    },

    socialLinks: [
      { icon: 'github', link: 'https://github.com/ruattd/swihomo' },
    ],

    footer: {
      message: 'Released under the <a href="https://github.com/ruattd/swihomo/blob/main/LICENSE">AGPL-3.0</a> license.',
      copyright: 'Copyright © 2026 ruattd',
    },
  },
})
