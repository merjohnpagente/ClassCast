/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./index.html'],
  theme: {
    extend: {
      // The same tokens the Flutter app reads in lib/theme/app_colors.dart.
      colors: {
        brand: '#3568F5',
        branddeep: '#2549B8',
        soft: '#E6EDFF',
        lav: '#8B7CFF',
        lavsoft: '#EFEBFF',
        ink: '#14213D',
        ink2: '#3E4A63',
        mut: '#6B7688',
        line: '#E4E9F2',
        night: '#0E1320',
        paper: '#F6F8FC',
        vidc: '#B4417A',
      },
      fontFamily: {
        sans: ['"Plus Jakarta Sans"', 'ui-sans-serif', 'system-ui', 'sans-serif'],
      },
    },
  },
  plugins: [],
}
