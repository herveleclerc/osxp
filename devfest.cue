package osxp

import (
    "dagger.io/dagger"
    "universe.dagger.io/docker"
    "strings"
    "github.com/herveleclerc/apptpl" 
)

dagger.#Plan & {
    client: {
      filesystem: {
          "./site": read: contents: dagger.#FS
      }
      
      env: {
        GITHUB_USER: string
        GITHUB_TOKEN: dagger.#Secret
        KUBECONFIGFILE: dagger.#Secret
      }
    }

    actions: {
      // Build de l'image avec buildkit
      build: docker.#Dockerfile & {
        // This is the Dockerfile context
        source: client.filesystem."./site".read.contents
      }  
      // Push de l'image sur la registry de github ghcr.io
      push: docker.#Push & {
        auth: {
          username: client.env.GITHUB_USER
          secret: client.env.GITHUB_TOKEN
        }
        image: build.output // Dépendance avec action build cette acction se déclenchera à la suite de `build`
        dest: "ghcr.io/herveleclerc/osxpdemo:1.0.1"
      }

      // Génération des manifests de l'application grace au CUE templating
      appmanifest: apptpl.#AppManifest & {
        name:  "osxp"
        image: strings.Trim(actions.push.result,"\n")
      }
      // Déploiement de l'image sur un cluster k8s
      deploy: {
        // Conteneur tool
        pull: docker.#Pull & {
          source: "lachlanevenson/k8s-kubectl"
        }

        // Configuration et lancement
			  run: docker.#Run & {
          env: {
            KUBECONFIG: "/tmp/.kube/config"
          }
			  	input: pull.output
			  	mounts: {
            kubeconfig: {
			  		  dest:     "/tmp/.kube/config"
              contents: client.env.KUBECONFIGFILE
              type:     "secret"
            }
            manifest: {
               dest: "/tmp/manifest.yaml"
               contents: actions.appmanifest.manifest
               type: "file"
            }
			  	}
			    command: {
            name: "apply"
            flags: {
              "-f": "/tmp/manifest.yaml"
            }
          }		
			  }
		}
  }
}
