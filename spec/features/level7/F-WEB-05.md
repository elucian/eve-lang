# F-WEB-05 evewp: edge and host

The Eve Web Portal as the production edge: host table by `Host` header (domains, subdomains, wildcards), static files, proxy to the Eve machine of each application, request log and limits; the host keeps each application in its own folder with versions, starts and supervises its machine, receives deploys, rollback (`code/evewp/README.md` sections 3, 5). Behind a reverse proxy for TLS.
