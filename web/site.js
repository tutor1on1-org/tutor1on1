(function () {
  const supportedLanguages = [
    {
      code: 'en',
      label: 'English',
      contact: { prefix: 'Need help or have a request? Email ', suffix: '' },
    },
  ]
  const releaseConfig = Object.freeze({
    githubRepo: 'tutor1on1-org/tutor1on1',
    appVersion: '1.0.1+2',
    releaseTag: 'v1.0.1',
    assets: Object.freeze({
      android: 'Tutor1on1.apk',
      windows: 'Tutor1on1.zip',
    }),
  })

  document.addEventListener('DOMContentLoaded', () => {
    const languageSwitcher = document.querySelector('[data-language-switcher]')
    applyReleaseLinks()
    appendContactEmail()

    if (!languageSwitcher) {
      return
    }

    populateLanguageOptions(languageSwitcher)
    languageSwitcher.value = 'en'
    languageSwitcher.disabled = true
  })

  function populateLanguageOptions(languageSwitcher) {
    languageSwitcher.textContent = ''

    for (const language of supportedLanguages) {
      const option = document.createElement('option')
      option.value = language.code
      option.textContent = language.label
      languageSwitcher.append(option)
    }
  }

  function appendContactEmail() {
    const footer = document.querySelector('.footer')
    if (!footer || footer.querySelector('[data-contact-email]')) {
      return
    }

    const line = document.createElement('p')
    line.setAttribute('data-contact-email', 'true')
    line.append(supportedLanguages[0].contact.prefix)

    const link = document.createElement('a')
    link.className = 'footer-link'
    link.href = 'mailto:tutor1on1.org@gmail.com'
    link.textContent = 'tutor1on1.org@gmail.com'
    line.append(link)

    if (supportedLanguages[0].contact.suffix) {
      line.append(supportedLanguages[0].contact.suffix)
    }

    footer.append(line)
  }

  function applyReleaseLinks() {
    const releaseBaseUrl = [
      'https://github.com',
      releaseConfig.githubRepo,
      'releases',
      'download',
      releaseConfig.releaseTag,
    ].join('/')

    const assetUrls = new Map([
      [releaseConfig.assets.android, `${releaseBaseUrl}/${releaseConfig.assets.android}`],
      [releaseConfig.assets.windows, `${releaseBaseUrl}/${releaseConfig.assets.windows}`],
    ])

    document.querySelectorAll('a[href]').forEach((link) => {
      const rawHref = String(link.getAttribute('href') || '')

      for (const [assetName, assetUrl] of assetUrls.entries()) {
        if (!rawHref.includes(assetName)) {
          continue
        }
        link.setAttribute('href', assetUrl)
        break
      }
    })

    replaceVisibleText('api.tutor1on1.org/downloads/', `${releaseBaseUrl}/`)
  }

  function replaceVisibleText(searchValue, replaceValue) {
    if (!document.body) {
      return
    }

    const walker = document.createTreeWalker(
      document.body,
      window.NodeFilter.SHOW_TEXT
    )
    const nodes = []

    while (walker.nextNode()) {
      nodes.push(walker.currentNode)
    }

    for (const node of nodes) {
      if (!node.nodeValue || !node.nodeValue.includes(searchValue)) {
        continue
      }
      node.nodeValue = node.nodeValue.replaceAll(searchValue, replaceValue)
    }
  }
})()
