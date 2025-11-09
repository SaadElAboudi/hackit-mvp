module.exports = {
    root: true,
    env: {
        node: true,
        es2022: true
    },
    extends: [
        'eslint:recommended',
        'plugin:import/recommended'
    ],
    parserOptions: {
        ecmaVersion: 2022,
        sourceType: 'module'
    },
    rules: {
        'no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
        'import/order': ['error', { 'newlines-between': 'always' }],
        'no-console': ['warn', { allow: ['warn', 'error'] }]
    },
    settings: {
        'import/resolver': {
            node: {
                extensions: ['.js']
            }
        }
    }
};
