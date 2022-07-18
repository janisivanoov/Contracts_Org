module.exports = {
  networks: {
    dev: {
      host: '127.0.0.1',
      port: 8546,
      network_id: '*',
    },
  },

  compilers: {
    solc: {
      version: '0.8.11',
    },
  },
}
