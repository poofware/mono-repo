export default {
  plugins: [
    { name: 'inlineStyles', params: { onlyMatchedOnce: false } },
    'convertStyleToAttrs',
    { name: 'removeAttrs', params: { attrs: '(filter|class)' } },
    { name: 'preset-default', params: { overrides: { removeUnknownsAndDefaults: false } } }
  ]
};
