# Deployment script for the traffic shifting demo

#!/bin/bash

set -e

echo "🚀 Starting Traffic Shifting Demo Deployment..."

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed or not in PATH"
    exit 1
fi

# Check if kind is available
if ! command -v kind &> /dev/null; then
    echo "❌ kind is not installed or not in PATH"
    echo "Please install Kind first: https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
    exit 1
fi

# Check if istioctl is available
if ! command -v istioctl &> /dev/null; then
    echo "❌ istioctl is not installed or not in PATH"
    echo "Please install Istio first: https://istio.io/latest/docs/setup/getting-started/"
    exit 1
fi

# Function to create Kind cluster using kind-config.yaml
create_kind_cluster() {
    echo "🔍 Checking for Kind cluster 'cluster1'..."
    if kind get clusters 2>/dev/null | grep -q "^cluster1$"; then
        echo "✅ Kind cluster 'cluster1' already exists"
    else
        echo "📦 Creating Kind cluster 'cluster1' using infrastructure/kind/kind-config.yaml..."
        kind create cluster --config infrastructure/kind/kind-config.yaml
        echo "✅ Kind cluster 'cluster1' created"
    fi
    kubectl config use-context kind-cluster1 &>/dev/null || true
}

# Function to install Istio using istio.yaml
install_istio() {
    echo "🔍 Checking Istio installation..."
    if kubectl get ns istio-system &>/dev/null && kubectl get service -n istio-system istio-ingressgateway &>/dev/null; then
        echo "✅ Istio is already installed"
    else
        echo "📦 Installing Istio using infrastructure/istio/istio.yaml..."
        istioctl install -f infrastructure/istio/istio.yaml -y
        echo "✅ Istio installed successfully"
    fi
}

# Function to check if a namespace has Istio injection enabled
check_istio_injection() {
    local namespace=${1:-traffic-shifting-demo}
    if kubectl get namespace "$namespace" -o jsonpath='{.metadata.labels.istio-injection}' 2>/dev/null | grep -q "enabled"; then
        echo "✅ Istio injection is enabled for namespace: $namespace"
        return 0
    else
        echo "⚠️  Istio injection is not enabled for namespace: $namespace"
        return 1
    fi
}

# Function to create namespace if it doesn't exist
create_namespace() {
    if kubectl get namespace traffic-shifting-demo &>/dev/null; then
        echo "✅ Namespace traffic-shifting-demo already exists"
    else
        echo "📦 Creating namespace traffic-shifting-demo..."
        kubectl apply -f manifests/base/namespace.yaml
        echo "✅ Created namespace traffic-shifting-demo"
    fi
    echo "🏷️  Enabling Istio injection for namespace: traffic-shifting-demo..."
    kubectl label namespace traffic-shifting-demo istio-injection=enabled --overwrite
}

# Function to create TMDB API key secret
create_secret() {
    # Check if namespace exists first
    if ! kubectl get namespace traffic-shifting-demo &>/dev/null; then
        echo "⚠️ Namespace doesn't exist, secret will be created after namespace creation"
        return 0
    fi
    
    if kubectl get secret tmdb-api-key -n traffic-shifting-demo &>/dev/null; then
        echo "✅ TMDB API key secret already exists"
    else
        read -p "Enter your TMDB API key (or press Enter to use a dummy key): " api_key
        api_key=${api_key:-"dummy_api_key_for_demo"}
        kubectl create secret generic tmdb-api-key \
            --from-literal=TMDB_API_KEY="$api_key" \
            -n traffic-shifting-demo
        echo "✅ Created TMDB API key secret"
    fi
}

# Function to deploy resources
deploy_resources() {
    echo "📦 Checking Kind cluster..."
    create_kind_cluster

    echo "📦 Checking Istio..."
    install_istio

    echo "📦 Creating namespace..."
    create_namespace
    
    echo "📦 Creating secret..."
    create_secret
    
    echo "📦 Deploying frontend components..."
    kubectl apply -f manifests/base/frontend.yaml
    
    echo "📦 Deploying backend components..."
    kubectl apply -f manifests/base/deployment-v1.yaml
    kubectl apply -f manifests/base/deployment-v2.yaml
    kubectl apply -f manifests/base/service.yaml
    
    echo "📦 Deploying networking components..."
    kubectl apply -f manifests/istio/gateway.yaml
    kubectl apply -f manifests/istio/destination-rule.yaml
    
    echo "📦 Deploying configuration maps..."
    kubectl apply -f manifests/base/configmap.yaml
    
    echo "📦 Setting initial traffic to 100% V1..."
    kubectl apply -f manifests/istio/virtual-services/virtual-service-100-0.yaml
    
    echo "⏳ Waiting for deployments to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/movie-frontend -n traffic-shifting-demo || echo "⚠️ Frontend deployment timeout"
    kubectl wait --for=condition=available --timeout=300s deployment/movie-backend-v1 -n traffic-shifting-demo || echo "⚠️ Backend v1 deployment timeout"
    kubectl wait --for=condition=available --timeout=300s deployment/movie-backend-v2 -n traffic-shifting-demo || echo "⚠️ Backend v2 deployment timeout"
    
    echo "✅ All deployments are ready!"
    echo "🎯 Traffic is set to 100% V1, 0% V2"
}

# Function to apply traffic configuration
apply_traffic_config() {
    local config=$1
    echo "🔄 Applying traffic configuration: $config"
    kubectl apply -f "manifests/istio/virtual-services/virtual-service-$config.yaml"
    echo "✅ Traffic configuration applied: $config"
}

# Function to show status
show_status() {
    echo "📊 Current Status"
    echo "================="
    echo "Frontend Pods:"
    kubectl get pods -l app=movie-frontend -n traffic-shifting-demo
    echo ""
    echo "Backend Pods:"
    kubectl get pods -l app=movie-backend -n traffic-shifting-demo
    echo ""
    echo "Services:"
    kubectl get services movie-frontend movie-backend -n traffic-shifting-demo
    echo ""
    echo "Virtual Services:"
    kubectl get virtualservices -n traffic-shifting-demo
    echo ""
    echo "Destination Rules:"
    kubectl get destinationrules -n traffic-shifting-demo
}

# Function to get ingress URL
get_ingress_url() {
    echo "🌐 Getting Ingress URL..."
    
    # Check if we're using LoadBalancer
    INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}' 2>/dev/null || true)
    
    if [[ -z "$INGRESS_HOST" ]]; then
        INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
    fi
    
    # Fallback to NodePort if LoadBalancer is not available
    if [[ -z "$INGRESS_HOST" ]]; then
        echo "⚠️ LoadBalancer not available. Using NodePort..."
        INGRESS_HOST=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null || true)
        if [[ -z "$INGRESS_HOST" ]]; then
            INGRESS_HOST=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)
        fi
        INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}' 2>/dev/null || true)
    fi
    
    if [[ -n "$INGRESS_HOST" && -n "$INGRESS_PORT" ]]; then
        echo "🔗 Frontend URL: http://$INGRESS_HOST:$INGRESS_PORT"
        echo "🔗 Backend API URL: http://$INGRESS_HOST:$INGRESS_PORT/api/"
    else
        echo "❌ Could not determine ingress URL"
        echo "Try: kubectl port-forward -n istio-system service/istio-ingressgateway 8080:80"
        echo "Then access: http://localhost:8080"
    fi
}

# Function to generate test traffic
generate_traffic() {
    echo "🔄 Generating test traffic..."
    
    # Get the ingress URL
    INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}' 2>/dev/null || true)
    
    if [[ -z "$INGRESS_HOST" ]]; then
        INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
    fi
    
    if [[ -z "$INGRESS_HOST" ]]; then
        INGRESS_HOST=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null || true)
        if [[ -z "$INGRESS_HOST" ]]; then
            INGRESS_HOST=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)
        fi
        INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}' 2>/dev/null || true)
    fi
    
    if [[ -n "$INGRESS_HOST" && -n "$INGRESS_PORT" ]]; then
        API_URL="http://$INGRESS_HOST:$INGRESS_PORT/api/"
        echo "Sending 20 requests to $API_URL"
        for i in {1..20}; do
            echo -n "Request $i: "
            response=$(curl -s -w "%{http_code}" "$API_URL" -o /tmp/response.txt)
            if [[ "$response" -eq 200 ]]; then
                echo "✅ Success"
            else
                echo "❌ Failed (HTTP $response)"
            fi
            sleep 0.5
        done
    else
        echo "❌ Could not get ingress URL for traffic generation"
        echo "Try running: kubectl port-forward -n istio-system service/istio-ingressgateway 8080:80"
        echo "Then test with: curl http://localhost:8080/api/"
    fi
}

# Function to test traffic splitting
test_traffic_splitting() {
    echo "🧪 Testing traffic splitting..."
    
    # Deploy load test pod
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: traffic-test
  namespace: traffic-shifting-demo
spec:
  containers:
  - name: curl
    image: curlimages/curl:latest
    command: ["/bin/sh"]
    args: ["-c", "while true; do curl -s http://movie-backend:8000/api/movies | head -1; sleep 1; done"]
  restartPolicy: Never
EOF
    
    echo "⏳ Load test pod deployed. Check logs with:"
    echo "kubectl logs -f traffic-test -n traffic-shifting-demo"
}

# Function to cleanup
cleanup() {
    echo "🧹 Cleaning up resources..."
    kubectl delete -f manifests/base/frontend.yaml --ignore-not-found=true
    kubectl delete -f manifests/base/deployment-v1.yaml --ignore-not-found=true
    kubectl delete -f manifests/base/deployment-v2.yaml --ignore-not-found=true
    kubectl delete -f manifests/base/service.yaml --ignore-not-found=true
    kubectl delete -f manifests/istio/gateway.yaml --ignore-not-found=true
    kubectl delete -f manifests/istio/destination-rule.yaml --ignore-not-found=true
    kubectl delete -f manifests/base/configmap.yaml --ignore-not-found=true
    kubectl delete -f manifests/istio/virtual-services/virtual-service-100-0.yaml --ignore-not-found=true
    kubectl delete -f manifests/istio/virtual-services/virtual-service-80-20.yaml --ignore-not-found=true
    kubectl delete -f manifests/istio/virtual-services/virtual-service-50-50.yaml --ignore-not-found=true
    kubectl delete -f manifests/istio/virtual-services/virtual-service-0-100.yaml --ignore-not-found=true
    kubectl delete pod traffic-test -n traffic-shifting-demo --ignore-not-found=true
    kubectl delete secret tmdb-api-key -n traffic-shifting-demo --ignore-not-found=true
    kubectl delete namespace traffic-shifting-demo --ignore-not-found=true
    echo "✅ Cleanup completed!"
}

# Main menu
show_menu() {
    echo ""
    echo "🎛️ Traffic Shifting Demo Menu"
    echo "=============================="
    echo "1. Deploy all resources (Kind cluster, Istio, App)"
    echo "2. Set traffic to 100% V1, 0% V2"
    echo "3. Set traffic to 80% V1, 20% V2"
    echo "4. Set traffic to 50% V1, 50% V2"
    echo "5. Set traffic to 0% V1, 100% V2"
    echo "6. Show current status"
    echo "7. Get ingress URL"
    echo "8. Generate test traffic"
    echo "9. Test traffic splitting"
    echo "10. Cleanup resources"
    echo "0. Exit"
    echo ""
}

# Check prerequisites (if cluster is active)
if kubectl cluster-info &>/dev/null; then
    check_istio_injection traffic-shifting-demo || true
fi

# Main execution
if [[ $# -eq 0 ]]; then
    # Interactive mode
    while true; do
        show_menu
        read -p "Choose an option (0-10): " choice
        
        case $choice in
            1)
                deploy_resources
                ;;
            2)
                apply_traffic_config "100-0"
                ;;
            3)
                apply_traffic_config "80-20"
                ;;
            4)
                apply_traffic_config "50-50"
                ;;
            5)
                apply_traffic_config "0-100"
                ;;
            6)
                show_status
                ;;
            7)
                get_ingress_url
                ;;
            8)
                generate_traffic
                ;;
            9)
                test_traffic_splitting
                ;;
            10)
                cleanup
                ;;
            0)
                echo "👋 Goodbye!"
                exit 0
                ;;
            *)
                echo "❌ Invalid option. Please choose 0-10."
                ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
else
    # Non-interactive mode
    case $1 in
        deploy)
            deploy_resources
            ;;
        cleanup)
            cleanup
            ;;
        status)
            show_status
            ;;
        url)
            get_ingress_url
            ;;
        test)
            generate_traffic
            ;;
        *)
            echo "Usage: $0 [deploy|cleanup|status|url|test]"
            echo "Or run without arguments for interactive mode"
            ;;
    esac
fi
