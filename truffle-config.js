module.exports = {
    networks: {
        development: {
            host: "127.0.0.1",
            port: 18567,
            network_id: "*",
            from: '0x458837630b4874d86d004b4fc7d3c34e274e64ee'
        }
    },
    compilers: {
        solc: {
            version: "^0.5.0",
            settings: {
                optimizer: {
                    enabled: true,
                    runs: 200
                },
            }
        }
    }
};
