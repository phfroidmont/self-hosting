kubectl run sshd-data --image=panubo/sshd --rm -ti --restart=Never --overrides='
{
  "metadata": {
      "labels": {
          "app": "sshd-data"
      }
  },
  "spec": {
      "containers": [
          {
              "stdin": true,
              "tty": true,
              "name": "sshd-data",
              "image": "panubo/sshd",
              "env": [
                  {
                      "name":"SSH_USERS",
                      "value":"storage1:1042:1042"
                  },
                  {
                      "name":"SSH_ENABLE_ROOT",
                      "value":"true"
                  }
              ],
              "volumeMounts": [
                  {
                      "name": "data",
                      "mountPath": "/data"
                  },
                  {
                      "name": "authorized-keys",
                      "mountPath": "/etc/authorized_keys/root",
                      "subPath": "root"
                  }
              ]
          }
      ],
      "volumes": [
          {
              "name": "data",
              "flexVolume": {
                  "driver": "ceph.rook.io/rook",
                  "fsType": "ceph",
                  "options": {
                      "fsName": "ceph-fs",
                      "clusterNamespace" : "rook-ceph"
                  }
               }
          },
          {
              "name": "authorized-keys",
              "configMap": {
                  "name": "sshd-authorized-keys",
                  "defaultMode": 420
              }
          }
      ]
  }
}
'
