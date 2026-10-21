# F-WEB-07 The Eve Web framework

Eve (a dialect with a browser profile) written once and compiled to WebAssembly modules that run in the page: stage W1 the VM in Wasm running source or `.evb`, stage W2 a typed subset compiled to Wasm; shared modules with the server; a fixed generated loader shim, no JavaScript written by the developer (`code/evewp/README.md` section 7). Needs F-VM-09, F-WEB-01, F-WEB-02.
