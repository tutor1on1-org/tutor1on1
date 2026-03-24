(function () {
  const languageStorageKey = 'tutor1on1-language'
  const currentPath = window.location.pathname || '/'
  const currentLanguage = currentPath === '/zh' || currentPath.startsWith('/zh/') ? 'zh' : 'en'
  const preferredLanguage = normalizeLanguage(
    window.localStorage.getItem(languageStorageKey) || detectDeviceLanguage()
  )
  const targetPath = mapPathToLanguage(currentPath, preferredLanguage)

  if (targetPath !== currentPath) {
    window.location.replace(`${targetPath}${window.location.search}${window.location.hash}`)
    return
  }

  document.addEventListener('DOMContentLoaded', () => {
    const languageSwitcher = document.querySelector('[data-language-switcher]')
    appendContactEmail()

    if (!languageSwitcher) {
      return
    }

    languageSwitcher.value = currentLanguage
    languageSwitcher.addEventListener('change', (event) => {
      const nextLanguage = normalizeLanguage(event.target.value)
      const nextPath = mapPathToLanguage(window.location.pathname || '/', nextLanguage)

      window.localStorage.setItem(languageStorageKey, nextLanguage)

      if (nextPath !== window.location.pathname) {
        window.location.assign(`${nextPath}${window.location.search}${window.location.hash}`)
      }
    })
  })

  function detectDeviceLanguage() {
    const candidates = Array.isArray(window.navigator.languages) && window.navigator.languages.length > 0
      ? window.navigator.languages
      : [window.navigator.language || 'en']

    return candidates.some((candidate) => normalizeLanguage(candidate) === 'zh') ? 'zh' : 'en'
  }

  function normalizeLanguage(language) {
    return String(language).toLowerCase().startsWith('zh') ? 'zh' : 'en'
  }

  function mapPathToLanguage(pathname, language) {
    if (language === 'zh') {
      if (pathname === '/zh' || pathname === '/zh/') {
        return '/zh/'
      }

      if (pathname.startsWith('/zh/')) {
        return pathname
      }

      return pathname === '/' ? '/zh/' : `/zh${pathname}`
    }

    if (pathname === '/zh' || pathname === '/zh/') {
      return '/'
    }

    if (pathname.startsWith('/zh/')) {
      const englishPath = pathname.slice(3)
      return englishPath.length === 0 ? '/' : englishPath
    }

    return pathname
  }

  function appendContactEmail() {
    const footer = document.querySelector('.footer')
    if (!footer || footer.querySelector('[data-contact-email]')) {
      return
    }

    const line = document.createElement('p')
    line.setAttribute('data-contact-email', 'true')

    if (currentLanguage === 'zh') {
      line.append('有任何需求，请发邮件到 ')
    } else {
      line.append('Need help or have a request? Email ')
    }

    const link = document.createElement('a')
    link.className = 'footer-link'
    link.href = 'mailto:tutor1on1.org@gmail.com'
    link.textContent = 'tutor1on1.org@gmail.com'
    line.append(link)
    footer.append(line)
  }
})()
