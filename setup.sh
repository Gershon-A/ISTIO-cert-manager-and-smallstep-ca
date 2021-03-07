
#!/bin/bash
set -e # exit on error

# Helper functions
echoerr() { 
    tput bold;
    tput setaf 1;
    echo "$@";
    tput sgr0; 1>&2; }
# Prints success/info $MESSAGE in green foreground color
#
# For e.g. You can use the convention of using GREEN color for [S]uccess messages
green_echo() {
    echo -e "\x1b[1;32m[S] $SELF_NAME: $MESSAGE\e[0m"
}

simple_green_echo() {
    echo -e "\x1b[1;32m$MESSAGE\e[0m"
}
blue_echo() {
    echo -e "\x1b[1;34m[I] $SELF_NAME: $MESSAGE\e[0m"
}

simple_blue_echo() {
    echo -e "\x1b[1;34m$MESSAGE\e[0m"
}
# Define Directory
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_usage() {
    echo "Create \"StepIssuer\" "
    echo "  -h                   --help                        - Show usage information"
    echo "  -ns=                 --name-space=                 - Should be created in the same name space where deployment is. For initial setup, use \"istio-system\""
    echo "  -f                   --force                       - Force the operation (don't wait for user input)"
    echo ""
    echo "Example usage: ./$(basename $0) -ns=istio-system "
}

# Prepare env and path solve the docker copy on windows when using bash
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        MYPATH=$PWD
        echo "Operation System dedected is:$OSTYPE"
        echo "MYPATH set to: $MYPATH"
        echo "HOME set to: $HOME"
elif [[ "$OSTYPE" == "darwin"* ]]; then
        # Mac OSX
        MYPATH=$PWD
        echo "Operation System dedected is:$OSTYPE"
        echo "MYPATH set to: $MYPATH"
        echo "HOME set to: $HOME"
elif [[ "$OSTYPE" == "cygwin" ]]; then
        # POSIX compatibility layer and Linux environment emulation for Windows
        MYPATH="$(cygpath -w $PWD)"
        HOME="$(cygpath -w $HOME)"
        echo "Operation System dedected is:$OSTYPE"
        echo "MYPATH set to: $MYPATH"
        echo "HOME set to: $HOME"
elif [[ "$OSTYPE" == "msys" ]]; then
        # Lightweight shell and GNU utilities compiled for Windows (part of MinGW)
        MYPATH="$(cygpath -w $PWD)"
        HOME="$(cygpath -w $HOME)"
        echo "Operation System dedected is:$OSTYPE"
        echo "MYPATH set to: $MYPATH"
        echo "HOME set to: $HOME"
elif [[ "$OSTYPE" == "win32" ]]; then
        # I'm not sure this can happen.
        MYPATH="$(cygpath -w $PWD)"
        HOME="$(cygpath -w $HOME)"
        echo "Operation System dedected is:$OSTYPE"
        echo "MYPATH set to: $MYPATH"
        echo "HOME set to: $HOME"
elif [[ "$OSTYPE" == "freebsd"* ]]; then
        MYPATH=$PWD
        echo "Operation System dedected is:$OSTYPE"
        echo "MYPATH set to: $MYPATH"
        echo "HOME set to: $HOME"
fi
# Print all provided command line arguments
MESSAGE="Print all provided command line arguments" ; green_echo
echo $@ 
# Parse command line arguments
for i in "$@"
do
case $i in
    -h|--help)
    print_usage
    exit 0
    ;;
    -ns=*|--name-space=*)
    NAME_SPACE="${i#*=}"
    shift # past argument=value
    ;;
    -f|--force)
    FORCE=1
    ;;
    *)
    echoerr "ERROR: Unknown argument"
    print_usage
    exit 1
    # unknown option
    ;;
esac
done
# Validate mandatory input
if [ -z "$MYPATH" ]; then
    echoerr "Error: local path is not set"
    print_usage
    exit 1
fi
 if [ -z "$NAME_SPACE" ]; then
    echoerr "Error: NAME_SPACE is not set. Get avaliable namespaces: kubectl get namespaces"
    print_usage
    exit 1
fi

# Functions
# Step Issuer installation 
step-issuer_instalation(){

        helm repo add smallstep  https://smallstep.github.io/helm-charts &&\
        helm repo update && \
        helm install step-certificates smallstep/step-certificates --namespace $NAME_SPACE && \
        sleep 10 && \
        kubectl apply -f https://raw.githubusercontent.com/smallstep/step-issuer/master/config/crd/bases/certmanager.step.sm_stepissuers.yaml && \
        kubectl apply -f https://raw.githubusercontent.com/smallstep/step-issuer/master/config/samples/deployment.yaml

}

# ClusterIssuer installation 
clusterissuer_installation() {
    echo "Get the \"kid\":"
    echo ""
    export KID=$(kubectl -n $NAME_SPACE get -o jsonpath="{.data['ca\.json']}" configmaps/step-certificates-config | jq .authority.provisioners | grep  "kid" |  awk  '{ print $2 }' | cut -f2 -d"\"")
    echo "kid = $KID" | cat -v
    echo ""

    echo "Get the \"CABANDLE\":"
    export CABANDLE=$(kubectl -n $NAME_SPACE get -o jsonpath="{.data['root_ca\.crt']}" configmaps/step-certificates-certs | base64 |  tr -d \\n)
    echo "CABANDLE = $CABANDLE" | cat -v
    echo "Get the \"CA url\":"
    export CAURL=$(kubectl -n $NAME_SPACE get -o jsonpath="{.data['defaults\.json']}" configmaps/step-certificates-config | grep -oP '(?<="ca-url": ")[^"]*')
    echo "CAURL = $CAURL" | cat -v

      cat src/Step-Issuer-dev.yaml | \
      sed "s/NAME_SPACE/istio-system/" | \
      sed "s/CABANDLE/$CABANDLE/"| \
      sed "s/KID/$KID/" | \
      sed "s#CAURL#$CAURL#" | \
      kubectl apply -f - ;
                        }
### CertManager installation verification
MESSAGE="Verifying if \"cert-manager\" istalled. If not - install it" ; green_echo
## That kubectl always return exit code 0. But we need to trigger if exit code is 1.
## Here is probably can be a better solution to get correct exit code
kubectl get pods --namespace cert-manager  | grep  -w Running  && exit_status=$? || exit_status=$? 

if [ "$exit_status" = 1 ] 
then
    echo ".... cert-manager Not exists ...."
    echo "Installing \"crt-manager\" ...."
        kubectl apply -f kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.2.0/cert-manager.yaml
    echo "Installing \"SmallStep\" ...."
        issuer_result="$(step-issuer_instalation)"
        echo $issuer_result
    echo "Installing step-issuer ......"
        clusterissuer_result="$(clusterissuer_installation)"
        echo $clusterissuer_result
else
    echo "\"cert-manager\"  exists in name space \"cert-manager\""
    echo "Installing step-issuer ......"
        clusterissuer_result="$(clusterissuer_installation)"
        echo $clusterissuer_result
        for i in {0..5}; do echo -ne "$i"'\r'; sleep 1; done; echo 
    echo "Wait 10s and Checking if installed"
        for i in {0..10}; do echo -ne "$i"'\r'; sleep 1; done; echo 
    STATUS=$(kubectl get stepissuers.certmanager.step.sm -n $NAME_SPACE step-issuer -o json | jq -r '.status.conditions[].status')
    MESSAGE="Here is step-issuer named \"step-issuer\" with status \"$STATUS\" in namespace \"$NAME_SPACE\" " ; green_echo
        if [[ "${STATUS}" != "True"  ]]
        then
        echo "Something is going wrong. Please investigate: kubectl describe stepissuers.certmanager.step.sm -n $NAME_SPACE step-issuer"
        else
        echo "We are OK. \"spep-issuer\" was installed."
        fi
fi
