# Réponses à mes questions

## 1. Structure cible du repo

Vu la structure actuelle du repo (`p3/scripts`, `p3/confs`, `Makefile` simple, manifests YAML directs), la structure la plus cohérente pour le bonus est :

```text
bonus/
├── README.md
├── confs/
│   ├── gitlab-values.yaml
│   ├── gitlab-ingress-note.md
│   ├── argocd-gitlab-repo-secret.yaml
│   ├── argocd-app-from-gitlab.yaml
│   └── sample-app/
│       ├── deployment.yaml
│       ├── service.yaml
│       └── ingress.yaml
└── scripts/
    ├── install_gitlab.sh
    └── check_bonus.sh
```

Minimalement, ce qu’il faut vraiment pour le bonus est :
- `bonus/confs/gitlab-values.yaml`
- `bonus/confs/argocd-gitlab-repo-secret.yaml`
- `bonus/confs/argocd-app-from-gitlab.yaml`
- un dossier de manifests applicatifs versionnés dans GitLab, par exemple `bonus/confs/sample-app/`
- `bonus/scripts/install_gitlab.sh`

`README.md` est utile pour la soutenance, mais reste optionnel si tu gardes tout dans un seul tutoriel.

## 2. Faut-il utiliser Vagrant si tu es déjà dans une VM ?

Non, je ne le recommande pas ici.

Tu es déjà dans une VM Linux, donc ajouter Vagrant par-dessus ne t’apporte pas de bénéfice direct pour ce bonus. Ça ajoute une couche de complexité, plus de consommation RAM/CPU, et rend le debug plus pénible.

Vagrant peut quand même aider dans un seul cas : si tu veux démontrer une reprovision complète, jetable, identique d’une machine à l’autre. Pour travailler vite et proprement sur ce bonus, reste dans ta VM actuelle.

## 3. Comment installer et configurer GitLab localement pour ce lab ?

La méthode réaliste est bien le Helm chart officiel GitLab.

Le point important : GitLab est lourd. Pour un lab local, il faut une configuration réduite et il faut dire clairement que c’est le composant le plus gourmand du bonus. En pratique, vise au minimum :
- **CPU** : 4 vCPU
- **RAM** : 8 Go recommandés
- **Disque** : 20 à 30 Go libres

Avec moins, l’installation peut démarrer mais devenir instable ou laisser des pods en `Pending` / `CrashLoopBackOff`.

Le principe :
1. créer le namespace `gitlab`
2. ajouter le repo Helm officiel
3. installer GitLab avec un fichier `values` minimal
4. exposer GitLab via Traefik
5. créer un repo dans GitLab
6. donner à ArgoCD un accès HTTP(S) à ce repo via token

## 4. Faut-il un Ingress pour GitLab ?

Oui, ici oui.

Tu ne veux pas de `kubectl port-forward`, donc il faut un accès stable par hostname local. Comme P3 utilise déjà Traefik, l’option cohérente est d’exposer GitLab via Ingress.

Exemple d’URL locale :
- `http://gitlab.local.com:8080`

Pourquoi en HTTP ici ? Parce que pour un bonus local, c’est plus simple, plus reproductible, et ça évite d’ajouter la complexité TLS/certificats sur GitLab. HTTPS peut être mentionné comme optionnel, mais ne doit pas être la voie principale si tu veux un setup simple.

## 5. “Héberger GitLab” veut dire quoi dans ce contexte ?

Dans ce bonus, “héberger GitLab” veut dire :
- GitLab tourne **dans le cluster Kubernetes**
- ses composants tournent dans le namespace `gitlab`
- l’interface web est exposée via Traefik + Ingress
- les données GitLab sont persistées via les volumes créés par le chart
- ArgoCD consomme ensuite un repo Git hébergé par cette instance GitLab

Donc :
- **dans le cluster** : GitLab webservice, shell, sidekiq, postgres/redis/minio selon le chart
- **exposé vers toi** : l’interface web GitLab via hostname local
- **persistant** : les données GitLab stockées dans des PVC

## 6. Pourquoi c’est utile dans ce bonus ?

Pédagogiquement, ça montre la chaîne GitOps complète :
- un GitLab local pour héberger le code/manifests
- ArgoCD qui lit ce repo
- Kubernetes qui déploie automatiquement

Techniquement, ça te fait pratiquer :
- Helm
- GitLab self-hosted
- Ingress local
- credentials Git pour ArgoCD
- compatibilité entre plusieurs briques Kubernetes dans un même cluster

## 7. Comment ArgoCD communique avec GitLab ?

Le schéma conseillé pour ce lab est :
- **repo GitLab en HTTP**
- **authentification par token**
- **ArgoCD configuré avec un Secret repository**

Je recommande **HTTP(S) + token**, pas SSH, pour garder le bonus simple.

Pourquoi :
- SSH ajoute la gestion des clés
- il faut exposer GitLab Shell correctement
- ce n’est pas nécessaire pour un bonus minimal viable

Le flux recommandé :
1. tu crées un repo GitLab
2. tu crées un **Personal Access Token** ou **Project Access Token** avec `read_repository`
3. tu crées un Secret dans `argocd` avec l’URL du repo, le username, le token
4. ArgoCD lit ce repo et déploie l’application

## 8. Ce qui doit rester compatible avec la P3 existante

Il ne faut pas casser :
- ArgoCD déjà installé dans `argocd`
- Traefik déjà utilisé comme Ingress Controller
- l’application déjà déployée par P3
- le namespace `dev` déjà utilisé par l’Application ArgoCD existante

Concrètement :
- ne remplace pas le bootstrap actuel de P3
- n’utilise pas GitLab comme dépendance de démarrage initiale d’ArgoCD
- ajoute GitLab **après** que P3 fonctionne déjà
- crée une **nouvelle** Application ArgoCD pour le bonus, au lieu de casser l’existante

---

# Tutoriel bonus GitLab (pas à pas)

## 1. Arborescence finale proposée

```text
bonus/
├── confs/
│   ├── gitlab-values.yaml
│   ├── argocd-gitlab-repo-secret.yaml
│   ├── argocd-app-from-gitlab.yaml
│   └── sample-app/
│       ├── deployment.yaml
│       ├── service.yaml
│       └── ingress.yaml
└── scripts/
    ├── install_gitlab.sh
    └── check_bonus.sh
```

## 2. Pré-requis

**Obligatoire**
- ta P3 fonctionne déjà
- `kubectl`, `helm`, `docker`, `k3d` installés
- Traefik déjà en place via k3d/K3s
- assez de ressources machine

**Optionnel**
- TLS sur GitLab
- SSH GitLab Shell
- Runner GitLab

Installe Helm si besoin :

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```

## 3. Ajouter les hostnames locaux

Sur la machine hôte / VM :

```bash
sudo sh -c 'printf "\n127.0.0.1 gitlab.local.com\n127.0.0.1 app-bonus.local.com\n" >> /etc/hosts'
```

Si ton cluster n’écoute pas sur `127.0.0.1`, remplace par l’IP correcte de la VM.

## 4. Créer le namespace GitLab

```bash
kubectl create namespace gitlab
```

## 5. Créer `bonus/confs/gitlab-values.yaml`

Contenu minimal viable, orienté local, avec Traefik existant et sans dépendances inutiles :

```yaml
global:
  edition: ce
  hosts:
    domain: local.com
    externalIP: 127.0.0.1
    https: false
    gitlab:
      name: gitlab.local.com
  ingress:
    configureCertmanager: false
    class: traefik
    provider: traefik
  initialRootPassword:
    secret: gitlab-initial-root-password
    key: password

certmanager:
  install: false

nginx-ingress:
  enabled: false

prometheus:
  install: false

gitlab-runner:
  install: false

registry:
  enabled: false

minio:
  enabled: false

gitlab:
  gitlab-shell:
    enabled: false
```

Ce choix est volontairement minimal :
- pas de NGINX Ingress intégré
- pas de cert-manager
- pas de runner
- pas de registry
- pas de shell SSH
- accès Git via HTTP seulement

## 6. Créer le secret du mot de passe root GitLab

```bash
kubectl create secret generic gitlab-initial-root-password \
  -n gitlab \
  --from-literal=password='GitlabRoot123!' \
  --dry-run=client -o yaml | kubectl apply -f -
```

## 7. Installer GitLab avec Helm

```bash
helm repo add gitlab https://charts.gitlab.io/
helm repo update
helm upgrade --install gitlab gitlab/gitlab \
  -n gitlab \
  -f bonus/confs/gitlab-values.yaml \
  --timeout 20m
```

Vérifie :

```bash
kubectl get pods -n gitlab
helm status gitlab -n gitlab
```

## 8. Vérifier l’Ingress GitLab

```bash
kubectl get ingress -n gitlab
kubectl get svc -n gitlab
```

Tu dois obtenir un hostname GitLab exposé via Traefik. L’URL attendue est :

```text
http://gitlab.local.com:8080
```

Pourquoi `:8080` ? Parce que dans ta P3, k3d mappe le port externe `8080` vers le port `80` du load balancer.

## 9. Se connecter à GitLab

Dans le navigateur :
```text
http://gitlab.local.com:8080
```

Login :
- user : `root`
- password : `GitlabRoot123!`

Ensuite :
1. crée un groupe, par exemple `iot`
2. crée un repo, par exemple `bonus-app`

## 10. Ajouter les manifests applicatifs à versionner dans GitLab

Crée ces fichiers localement.

### `bonus/confs/sample-app/deployment.yaml`
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: bonus-app
  namespace: dev
spec:
  replicas: 1
  selector:
    matchLabels:
      app: bonus-app
  template:
    metadata:
      labels:
        app: bonus-app
    spec:
      containers:
        - name: bonus-app
          image: nginxdemos/hello:plain-text
          ports:
            - containerPort: 80
```

### `bonus/confs/sample-app/service.yaml`
```yaml
apiVersion: v1
kind: Service
metadata:
  name: bonus-app
  namespace: dev
spec:
  selector:
    app: bonus-app
  ports:
    - port: 80
      targetPort: 80
```

### `bonus/confs/sample-app/ingress.yaml`
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: bonus-app-ingress
  namespace: dev
spec:
  ingressClassName: traefik
  rules:
    - host: app-bonus.local.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: bonus-app
                port:
                  number: 80
```

Ensuite pousse ces fichiers dans le repo GitLab `bonus-app`.

Exemple :

```bash
git clone http://gitlab.local.com:8080/iot/bonus-app.git
cd bonus-app
mkdir -p manifests
cp /chemin/vers/bonus/confs/sample-app/*.yaml manifests/
git add .
git commit -m "add bonus app manifests"
git push origin main
```

## 11. Créer un token GitLab pour ArgoCD

Dans GitLab :
- va dans le projet
- crée un **Project Access Token** ou un **Personal Access Token**
- scope minimal : `read_repository`

Garde :
- username
- token
- URL du repo

Exemple de repo :
```text
http://gitlab.local.com:8080/iot/bonus-app.git
```

## 12. Créer le Secret repo pour ArgoCD

### `bonus/confs/argocd-gitlab-repo-secret.yaml`
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: gitlab-bonus-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  type: git
  url: http://gitlab.local.com:8080/iot/bonus-app.git
  username: root
  password: REPLACE_WITH_GITLAB_TOKEN
  insecure: "true"
```

Applique :

```bash
kubectl apply -f bonus/confs/argocd-gitlab-repo-secret.yaml
```

## 13. Créer la nouvelle Application ArgoCD

### `bonus/confs/argocd-app-from-gitlab.yaml`
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: bonus-app-from-gitlab
  namespace: argocd
spec:
  project: default
  source:
    repoURL: http://gitlab.local.com:8080/iot/bonus-app.git
    targetRevision: main
    path: manifests
  destination:
    server: https://kubernetes.default.svc
    namespace: dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

Applique :

```bash
kubectl apply -f bonus/confs/argocd-app-from-gitlab.yaml
```

## 14. Vérifier le flux complet

```bash
kubectl get pods -n gitlab
kubectl get ingress -n gitlab
kubectl get secrets -n argocd
kubectl get applications -n argocd
kubectl get all -n dev
```

Accès attendus :
- GitLab : `http://gitlab.local.com:8080`
- app bonus : `http://app-bonus.local.com:8080`

Ajoute si besoin dans `/etc/hosts` :
```text
127.0.0.1 gitlab.local.com
127.0.0.1 app-bonus.local.com
```

---

# Checklist de validation finale

```bash
helm list -n gitlab
kubectl get pods -n gitlab
kubectl get ingress -n gitlab
kubectl get svc -n gitlab
kubectl get applications -n argocd
kubectl describe application bonus-app-from-gitlab -n argocd
kubectl get all -n dev
curl -I http://gitlab.local.com:8080
curl -I http://app-bonus.local.com:8080
```

Tu dois pouvoir valider :
1. GitLab répond via Ingress
2. tu peux te connecter au GitLab web
3. le repo GitLab contient les manifests
4. ArgoCD voit le repo
5. l’Application ArgoCD est `Synced` et `Healthy`
6. l’app bonus répond via son hostname local

### Definition of Done
- [ ] `gitlab` namespace créé
- [ ] GitLab Helm installé et pods `Running`
- [ ] GitLab accessible via `http://gitlab.local.com:8080`
- [ ] repo GitLab créé et manifests poussés
- [ ] Secret repo ArgoCD appliqué
- [ ] Application ArgoCD appliquée
- [ ] app bonus accessible via `http://app-bonus.local.com:8080`
- [ ] P3 initiale toujours fonctionnelle

---

# FAQ / Problèmes courants

## Pods GitLab en `Pending`

Cause probable : pas assez de RAM/CPU.

Vérifie :
```bash
kubectl describe pod -n gitlab <pod-name>
kubectl get events -n gitlab --sort-by=.metadata.creationTimestamp
```

Solution :
- augmente la RAM/CPU de la VM
- garde le profil minimal
- n’active pas runner/registry/cert-manager inutilement

## GitLab ne répond pas via le navigateur

Vérifie :
```bash
kubectl get ingress -n gitlab
kubectl get svc -A | grep traefik
cat /etc/hosts
```

Assure-toi que `gitlab.local.com` pointe bien vers l’IP correcte de ta VM ou `127.0.0.1` selon ton setup.

## ArgoCD n’arrive pas à lire le repo GitLab

Vérifie :
- l’URL du repo dans le Secret
- le token
- le username
- le scope `read_repository`

Puis :
```bash
kubectl get secret gitlab-bonus-repo -n argocd -o yaml
kubectl describe application bonus-app-from-gitlab -n argocd
```

## Erreur certificat / TLS

Pour ce tutoriel, le chemin principal est **HTTP**, pas HTTPS. Donc si tu veux un setup simple, reste en HTTP.

Si tu passes en HTTPS plus tard :
- il faudra gérer le certificat
- éventuellement ajouter `insecureSkipVerify` côté ArgoCD selon ton cert local

## Le repo GitLab marche dans le navigateur, mais pas dans ArgoCD

Point important : un hostname résolu via `/etc/hosts` sur ta machine n’est pas forcément résolu de la même manière depuis les pods.

Pour un bonus simple et local, la solution la plus reproductible est de garder un hostname local simple et un cluster accessible via la même IP que ta machine/VM. Si besoin, adapte `gitlab.local.com` pour qu’il resolve vers l’IP réellement atteignable depuis le cluster.

## Est-ce qu’il faut absolument SSH pour GitLab ?

Non.

Pour ce bonus, **HTTP + token** est suffisant, plus simple, et plus propre à défendre en soutenance.

## Est-ce qu’il faut modifier l’Application ArgoCD existante de P3 ?

Non.

Il vaut mieux **ajouter une nouvelle Application** pour le bonus. C’est plus sûr, plus démontrable, et ça évite de casser la P3 obligatoire.
