(function () {
  const languageStorageKey = 'tutor1on1-language'
  const supportedLanguages = [
    {
      code: 'en',
      label: 'English',
      prefix: '',
      contact: { prefix: 'Need help or have a request? Email ', suffix: '' },
    },
    {
      code: 'zh',
      label: '简体中文',
      prefix: '/zh',
      contact: { prefix: '如有问题或需求，请发邮件到 ', suffix: '' },
    },
    {
      code: 'zh-tw',
      label: '繁體中文',
      prefix: '/zh-tw',
      contact: { prefix: '如有問題或需求，請寄信到 ', suffix: '' },
    },
    {
      code: 'ja',
      label: '日本語',
      prefix: '/ja',
      contact: { prefix: '質問や要望がある場合は ', suffix: ' までメールしてください。' },
    },
    {
      code: 'ko',
      label: '한국어',
      prefix: '/ko',
      contact: { prefix: '문의나 요청이 있으면 ', suffix: ' 으로 이메일을 보내 주세요.' },
    },
    {
      code: 'es',
      label: 'Español',
      prefix: '/es',
      contact: { prefix: 'Si necesita ayuda o tiene una solicitud, escriba a ', suffix: '' },
    },
    {
      code: 'fr',
      label: 'Français',
      prefix: '/fr',
      contact: { prefix: "Besoin d'aide ou d'une demande ? Écrivez à ", suffix: '' },
    },
    {
      code: 'de',
      label: 'Deutsch',
      prefix: '/de',
      contact: { prefix: 'Bei Fragen oder Wünschen schreiben Sie an ', suffix: '' },
    },
  ]
  const releaseConfig = Object.freeze({
    githubRepo: 'tutor1on1-org/tutor1on1',
    appVersion: '1.0.8',
    releaseTag: 'v1.0.8',
    downloadBaseUrl: 'https://api.tutor1on1.org/downloads',
    assets: Object.freeze({
      android: 'Tutor1on1-1.0.8.apk',
      windows: 'Tutor1on1-1.0.8.zip',
    }),
  })
  const languagesByCode = new Map(
    supportedLanguages.map((language) => [language.code, language])
  )
  const prefixedLanguages = supportedLanguages
    .filter((language) => language.prefix.length > 0)
    .sort((left, right) => right.prefix.length - left.prefix.length)
  const currentPath = canonicalizePath(window.location.pathname || '/')
  const currentLanguage = detectPathLanguage(currentPath)
  const storedLanguageRaw = window.localStorage.getItem(languageStorageKey)
  const storedLanguage = storedLanguageRaw
    ? normalizeLanguage(storedLanguageRaw)
    : null
  const preferredLanguage = storedLanguage || detectDeviceLanguage()
  const targetPath = mapPathToLanguage(currentPath, preferredLanguage)

  if (shouldRedirect(currentPath, targetPath, storedLanguage)) {
    window.location.replace(
      `${targetPath}${window.location.search}${window.location.hash}`
    )
    return
  }

  document.addEventListener('DOMContentLoaded', () => {
    const languageSwitcher = document.querySelector('[data-language-switcher]')
    applyReleaseLinks()
    appendContactEmail()

    if (!languageSwitcher) {
      return
    }

    enhanceLanguageSwitcher(languageSwitcher)
    languageSwitcher.value = currentLanguage
    languageSwitcher.addEventListener('change', (event) => {
      const nextLanguage = normalizeLanguage(event.target.value)
      const nextPath = mapPathToLanguage(
        canonicalizePath(window.location.pathname || '/'),
        nextLanguage
      )

      window.localStorage.setItem(languageStorageKey, nextLanguage)

      if (nextPath !== canonicalizePath(window.location.pathname || '/')) {
        window.location.assign(
          `${nextPath}${window.location.search}${window.location.hash}`
        )
      }
    })
  })

  function shouldRedirect(pathname, targetPath, storedLanguage) {
    if (targetPath === pathname) {
      return false
    }

    if (storedLanguage) {
      return true
    }

    return !hasExplicitLanguagePrefix(pathname)
  }

  function enhanceLanguageSwitcher(languageSwitcher) {
    populateLanguageOptions(languageSwitcher)

    if (languageSwitcher.parentElement?.classList.contains('lang-switcher')) {
      return
    }

    languageSwitcher.classList.remove('nav-action')

    const wrapper = document.createElement('span')
    wrapper.className = 'lang-switcher nav-action'

    const icon = document.createElement('span')
    icon.className = 'lang-icon'
    icon.setAttribute('aria-hidden', 'true')
    icon.textContent = String.fromCodePoint(0x1f310)

    languageSwitcher.parentNode.insertBefore(wrapper, languageSwitcher)
    wrapper.append(icon, languageSwitcher)
  }

  function populateLanguageOptions(languageSwitcher) {
    const previousValue = languagesByCode.has(languageSwitcher.value)
      ? languageSwitcher.value
      : currentLanguage
    languageSwitcher.textContent = ''

    for (const language of supportedLanguages) {
      const option = document.createElement('option')
      option.value = language.code
      option.textContent = language.label
      languageSwitcher.append(option)
    }

    languageSwitcher.value = previousValue
  }

  function detectDeviceLanguage() {
    const candidates =
      Array.isArray(window.navigator.languages) &&
      window.navigator.languages.length > 0
        ? window.navigator.languages
        : [window.navigator.language || 'en']

    for (const candidate of candidates) {
      const normalized = normalizeLanguage(candidate)
      if (languagesByCode.has(normalized)) {
        return normalized
      }
    }

    return 'en'
  }

  function normalizeLanguage(language) {
    const value = String(language || '')
      .trim()
      .toLowerCase()
      .replace(/_/g, '-')

    if (
      value === 'zh-tw' ||
      value === 'zh-hk' ||
      value === 'zh-mo' ||
      value === 'zh-hant'
    ) {
      return 'zh-tw'
    }

    if (value.startsWith('zh-')) {
      return value.includes('hant') ? 'zh-tw' : 'zh'
    }

    if (value.startsWith('zh')) {
      return 'zh'
    }

    if (value.startsWith('ja')) {
      return 'ja'
    }

    if (value.startsWith('ko')) {
      return 'ko'
    }

    if (value.startsWith('es')) {
      return 'es'
    }

    if (value.startsWith('fr')) {
      return 'fr'
    }

    if (value.startsWith('de')) {
      return 'de'
    }

    return 'en'
  }

  function canonicalizePath(pathname) {
    let path = String(pathname || '/')

    if (!path.startsWith('/')) {
      path = `/${path}`
    }

    path = path.replace(/\/{2,}/g, '/')

    if (!path.includes('.') && !path.endsWith('/')) {
      path += '/'
    }

    return path
  }

  function hasExplicitLanguagePrefix(pathname) {
    return prefixedLanguages.some((language) =>
      pathname === `${language.prefix}/` ||
      pathname.startsWith(`${language.prefix}/`)
    )
  }

  function detectPathLanguage(pathname) {
    const language = prefixedLanguages.find(
      (candidate) =>
        pathname === `${candidate.prefix}/` ||
        pathname.startsWith(`${candidate.prefix}/`)
    )

    return language ? language.code : 'en'
  }

  function mapPathToLanguage(pathname, languageCode) {
    const suffix = stripLanguagePrefix(pathname)
    const targetLanguage =
      languagesByCode.get(languageCode) || languagesByCode.get('en')

    if (!targetLanguage.prefix) {
      return suffix
    }

    return suffix === '/'
      ? `${targetLanguage.prefix}/`
      : `${targetLanguage.prefix}${suffix}`
  }

  function stripLanguagePrefix(pathname) {
    const language = prefixedLanguages.find(
      (candidate) =>
        pathname === `${candidate.prefix}/` ||
        pathname.startsWith(`${candidate.prefix}/`)
    )

    if (!language) {
      return pathname
    }

    if (pathname === `${language.prefix}/`) {
      return '/'
    }

    const strippedPath = pathname.slice(language.prefix.length)
    return strippedPath.length === 0 ? '/' : strippedPath
  }

  function appendContactEmail() {
    const footer = document.querySelector('.footer')
    if (!footer || footer.querySelector('[data-contact-email]')) {
      return
    }

    const contact =
      languagesByCode.get(currentLanguage)?.contact ||
      languagesByCode.get('en').contact
    const line = document.createElement('p')
    line.setAttribute('data-contact-email', 'true')
    line.append(contact.prefix)

    const link = document.createElement('a')
    link.className = 'footer-link'
    link.href = 'mailto:tutor1on1.org@gmail.com'
    link.textContent = 'tutor1on1.org@gmail.com'
    line.append(link)

    if (contact.suffix) {
      line.append(contact.suffix)
    }

    footer.append(line)
  }

  function applyReleaseLinks() {
    const downloadBaseUrl = String(releaseConfig.downloadBaseUrl || '').replace(
      /\/+$/,
      ''
    )

    const assetUrls = new Map([
      [releaseConfig.assets.android, `${downloadBaseUrl}/${releaseConfig.assets.android}`],
      [releaseConfig.assets.windows, `${downloadBaseUrl}/${releaseConfig.assets.windows}`],
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

    replaceVisibleText('Tutor1on1.apk', releaseConfig.assets.android)
    replaceVisibleText('Tutor1on1.zip', releaseConfig.assets.windows)
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
