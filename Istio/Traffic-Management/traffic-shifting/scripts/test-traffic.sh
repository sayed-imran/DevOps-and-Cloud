#!/bin/bash

# Traffic Distribution Test Script
# This script tests the traffic distribution between V1 and V2 of the movie backend

echo "🧪 Traffic Distribution Test for Movie Backend"
echo "=============================================="

# Function to get ingress URL
get_ingress_url() {
    INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}' 2>/dev/null)
    
    if [[ -z "$INGRESS_HOST" ]]; then
        INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
    fi
    
    if [[ -z "$INGRESS_HOST" ]]; then
        INGRESS_HOST=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null)
        if [[ -z "$INGRESS_HOST" ]]; then
            INGRESS_HOST=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
        fi
        INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}' 2>/dev/null)
    fi
    
    if [[ -n "$INGRESS_HOST" && -n "$INGRESS_PORT" ]]; then
        echo "http://$INGRESS_HOST:$INGRESS_PORT/api/"
    else
        echo ""
    fi
}

# Function to test traffic distribution
test_traffic() {
    local num_requests=${1:-100}
    local url=$(get_ingress_url)
    
    if [[ -z "$url" ]]; then
        echo "❌ Could not determine ingress URL"
        echo "Try running: kubectl port-forward -n istio-system service/istio-ingressgateway 8080:80"
        echo "Then test manually with: curl http://localhost:8080/api/"
        exit 1
    fi
    
    echo "🔗 Testing URL: $url"
    echo "📊 Sending $num_requests requests to analyze traffic distribution..."
    echo ""
    
    local v1_count=0
    local v2_count=0
    local failed_count=0
    
    for i in $(seq 1 $num_requests); do
        local response=$(curl -s "$url" --max-time 5 2>/dev/null)
        local status=$?
        
        if [[ $status -eq 0 && -n "$response" ]]; then
            # Try to detect which version based on response content
            # Since both versions return JSON, we'll check response size or specific patterns
            if echo "$response" | grep -q "bollywood"; then
                v1_count=$((v1_count + 1))
                echo -n "1"
            elif echo "$response" | grep -q "hollywood"; then
                v2_count=$((v2_count + 1))
                echo -n "2"
            else
                # If we can't distinguish, consider it v1 (default)
                v1_count=$((v1_count + 1))
                echo -n "1"
            fi
        else
            failed_count=$((failed_count + 1))
            echo -n "X"
        fi
        
        # Add a newline every 20 requests for readability
        if [[ $((i % 20)) -eq 0 ]]; then
            echo " ($i/$num_requests)"
        fi
        
        sleep 0.1
    done
    
    echo ""
    echo ""
    echo "📈 Results Summary"
    echo "=================="
    echo "Total Requests: $num_requests"
    echo "V1 Responses:   $v1_count ($(printf "%.1f" $(echo "scale=2; $v1_count * 100 / $num_requests" | bc))%)"
    echo "V2 Responses:   $v2_count ($(printf "%.1f" $(echo "scale=2; $v2_count * 100 / $num_requests" | bc))%)"
    echo "Failed:         $failed_count ($(printf "%.1f" $(echo "scale=2; $failed_count * 100 / $num_requests" | bc))%)"
    echo ""
    
    # Show current VirtualService configuration
    echo "🎛️ Current Traffic Configuration"
    echo "================================="
    kubectl get virtualservice movie-backend -o jsonpath='{.spec.http[0].route}' 2>/dev/null || echo "No VirtualService found"
}

# Function to show current configuration
show_config() {
    echo "🔍 Current VirtualService Configuration"
    echo "======================================"
    echo "Active VirtualServices:"
    kubectl get virtualservices -o wide
    echo ""
    echo "Destination Rules:"
    kubectl get destinationrules -o wide
    echo ""
    echo "Backend Pods Status:"
    kubectl get pods -l app=movie-backend -o wide
}

# Function to monitor real-time traffic
monitor_traffic() {
    echo "🔄 Real-time Traffic Monitoring"
    echo "==============================="
    echo "Press Ctrl+C to stop monitoring"
    echo ""
    
    local url=$(get_ingress_url)
    if [[ -z "$url" ]]; then
        echo "❌ Could not determine ingress URL"
        exit 1
    fi
    
    local request_count=0
    local v1_count=0
    local v2_count=0
    
    while true; do
        local response=$(curl -s "$url" --max-time 2 2>/dev/null)
        local status=$?
        
        if [[ $status -eq 0 && -n "$response" ]]; then
            request_count=$((request_count + 1))
            
            if echo "$response" | grep -q "bollywood"; then
                v1_count=$((v1_count + 1))
                echo -e "\r🟢 Request $request_count: V1 | V1: $v1_count V2: $v2_count | Ratio: $(printf "%.0f" $(echo "scale=0; $v1_count * 100 / $request_count" | bc))%:$(printf "%.0f" $(echo "scale=0; $v2_count * 100 / $request_count" | bc))%"
            elif echo "$response" | grep -q "hollywood"; then
                v2_count=$((v2_count + 1))
                echo -e "\r🔵 Request $request_count: V2 | V1: $v1_count V2: $v2_count | Ratio: $(printf "%.0f" $(echo "scale=0; $v1_count * 100 / $request_count" | bc))%:$(printf "%.0f" $(echo "scale=0; $v2_count * 100 / $request_count" | bc))%"
            else
                v1_count=$((v1_count + 1))
                echo -e "\r🟡 Request $request_count: V1 | V1: $v1_count V2: $v2_count | Ratio: $(printf "%.0f" $(echo "scale=0; $v1_count * 100 / $request_count" | bc))%:$(printf "%.0f" $(echo "scale=0; $v2_count * 100 / $request_count" | bc))%"
            fi
        else
            echo -e "\r❌ Request failed"
        fi
        
        sleep 1
    done
}

# Main script
case "$1" in
    "config")
        show_config
        ;;
    "test")
        NUM_REQUESTS=${2:-100}
        test_traffic $NUM_REQUESTS
        ;;
    "monitor")
        monitor_traffic
        ;;
    *)
        echo "Usage: $0 [test|config|monitor] [num_requests]"
        echo ""
        echo "Commands:"
        echo "  test [num]  - Test traffic distribution with num requests (default: 100)"
        echo "  config      - Show current VirtualService configuration"
        echo "  monitor     - Real-time traffic monitoring (Ctrl+C to stop)"
        echo ""
        echo "Examples:"
        echo "  $0 test 100     # Test with 100 requests"
        echo "  $0 config       # Show current configuration"  
        echo "  $0 monitor      # Monitor traffic in real-time"
        exit 1
        ;;
esac
