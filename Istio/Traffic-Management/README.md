# Istio Traffic Management Demos

This repository contains comprehensive demonstrations of Istio service mesh traffic management capabilities, showcasing different deployment strategies and traffic control patterns in Kubernetes environments.

## Repository Structure

```
Traffic-Management/
├── flagger-canary-release/     # Automated canary deployments with Flagger
└── traffic-shifting/           # Manual traffic shifting demonstrations
```

## Demonstrations Overview

### 1. Traffic Shifting (`traffic-shifting/`)
**Purpose**: Manual traffic control and weighted routing between service versions

**Key Features**:
- Weighted traffic distribution (100/0, 80/20, 50/50, 0/100)
- A/B testing capabilities
- Blue-green deployment patterns
- Manual canary deployment control

**Technologies**:
- Istio VirtualService for traffic routing
- DestinationRule for load balancing
- Kubernetes Deployments (v1 and v2)
- React frontend with movie catalog backend

**Components**:
- Backend V1: Bollywood movies (TMDB API)
- Backend V2: Hollywood movies (TMDB API) 
- Frontend: React-based movie catalog UI
- Istio Gateway for external traffic

### 2. Flagger Canary Release (`flagger-canary-release/`)
**Purpose**: Automated progressive delivery with canary analysis

**Key Features**:
- Automated traffic shifting based on metrics
- Prometheus-based canary analysis
- Automatic rollback on failure detection
- Load testing integration
- Success rate and latency monitoring

**Technologies**:
- Flagger CRD for automated canary deployments
- Istio service mesh integration
- Prometheus metrics collection
- Kubernetes native resources

**Components**:
- Primary workload (stable version)
- Canary workload (new version)
- Movie frontend application
- Automated testing framework

## Metadata

### Repository Information
- **Domain**: DevOps and Cloud Technologies
- **Technology Stack**: Kubernetes, Istio Service Mesh
- **Focus Area**: Traffic Management and Progressive Delivery
- **Deployment Patterns**: Canary, Blue-Green, A/B Testing
- **Date Created**: 2025
- **Maintained By**: DevOps Engineering Team

### Prerequisites
- **Traffic Shifting**: Docker, Kind, kubectl, and istioctl. The deploy script creates a Kind cluster and installs Istio for you.
- **Flagger Canary Release**: a Kubernetes cluster, kubectl, istioctl, and Helm. The deploy script can install Istio, Prometheus, Flagger, and the Flagger load tester.
- Grafana and Kiali are optional, for dashboards.

### Use Cases
- **Development Teams**: Learn progressive deployment strategies
- **DevOps Engineers**: Implement traffic management patterns
- **SRE Teams**: Reduce deployment risks through gradual rollouts
- **Platform Engineers**: Build robust deployment pipelines

## Getting Started

Run each demo's scripts from that demo's directory, because they use relative paths.

| | Traffic Shifting | Flagger Canary Release |
|---|---|---|
| Directory | `traffic-shifting/` | `flagger-canary-release/` |
| Setup guide | [`docs/SETUP.md`](traffic-shifting/docs/SETUP.md) | [`SETUP.md`](flagger-canary-release/SETUP.md) |
| Deploy | `./scripts/deploy.sh` | `./deploy.sh` |
| Exercise it | `./scripts/test-traffic.sh test 100` | `kubectl set env deployment/movie-backend DATA_DIR=hollywood-data`, then `kubectl get canary canary-release -w` |
| Clean up | `./scripts/deploy.sh cleanup` | `./cleanup.sh` |

See each demo's `README.md` for the full walkthrough.

## Architecture Patterns

### Traffic Shifting Pattern
```
Client → Istio Gateway → VirtualService → DestinationRule → Services (v1/v2)
```

### Flagger Canary Pattern  
```
Client → Istio Gateway → Flagger Canary → Auto-generated VirtualService → Services (primary/canary)
```

## Monitoring and Observability

Both demos work with Istio's observability add-ons when they're installed:
- **Prometheus**: Metrics collection and analysis (required by Flagger)
- **Grafana**: Visualization dashboards
- **Kiali**: Service mesh topology and traffic flow
- **Jaeger**: Distributed tracing (optional)

## Best Practices Demonstrated

- **Gradual Traffic Shifting**: Minimize deployment risk
- **Automated Rollback**: Quick recovery from failures  
- **Metrics-Based Decisions**: Data-driven deployment validation
- **Load Testing**: Validate performance under traffic
- **Infrastructure as Code**: Reproducible deployments

## Contributing

When adding new traffic management demonstrations:
1. Follow the established directory structure
2. Include comprehensive documentation
3. Provide setup, deployment, and cleanup scripts
4. Add monitoring and testing capabilities
5. Update this root README with new metadata

## Support

For questions or issues:
- Review individual demonstration README files
- Check Istio documentation for service mesh concepts
- Consult Flagger documentation for automated canary deployments
- Refer to Kubernetes documentation for cluster operations

---

**Last Updated**: October 2026  
**Istio Version Compatibility**: 1.20+  
**Kubernetes Version**: 1.28+
