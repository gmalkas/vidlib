const defaultTheme = require('tailwindcss/defaultTheme.js')

module.exports = {
  mode: 'jit',
  purge: [
    '../lib/vidlib_web/templates/**/*.html.*',
    '../lib/vidlib_web/live/*.html.heex',
    '../lib/vidlib_web/views/**/*.ex',
    './js/**/*.{js,jsx,ts,tsx}',
  ],
  theme: {
    extend: {
      fontFamily: {
        sans: ['Inter var', ...defaultTheme.fontFamily.sans],
        serif: ['Nerko One', ...defaultTheme.fontFamily.serif],
      },
    },
  },
  variants: {
    extend: {
      visibility: ['hover', 'group-hover'],
      display: ['hover', 'group-hover'],
    }
  },
  plugins: [
    require('@tailwindcss/forms'),
    require('@tailwindcss/typography'),
    require('@tailwindcss/aspect-ratio'),
  ],
}
