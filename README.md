# Monitoring with NestJS, Prometheus, and Grafana

A real production incident showed how a lack of proper monitoring can lead to extended downtime, customer dissatisfaction, and lost revenue. In one case, an application outage took six hours to recover because the team lacked effective monitoring and alerting. This project demonstrates how to set up basic monitoring for a NestJS web application using Prometheus for metrics collection and Grafana for visualization—all on your local machine with Docker.

- A **NestJS web application** (named `nestjs-observability-stack`) exposing a REST API.
- A **Prometheus** server to scrape metrics.
- A **Grafana** instance to visualize the data.


A high-level diagram of the setup:

         +-------------------+
         |   NestJS App      |
         | (metr101 service) |
         +-------------------+
                |  exposes /metrics
                v
         +-------------------+
         |   Prometheus      |
         +-------------------+
                |  provides data for
                v
         +-------------------+
         |    Grafana        |
         +-------------------+


## Prerequisites

Ensure you have the following installed on your machine:
- [Node.js](https://nodejs.org/)
- [Docker](https://www.docker.com/)

## Setting Up the NestJS Application

1. **Create a new NestJS application:**

   Execute the following command and choose `npm` as your package manager when prompted:

   ```bash
   npx @nestjs/cli new nestjs-observability-stack
   ```

2. **Install dependencies and start the application:**

   Navigate into the project directory and run:

   ```bash
   cd nestjs-observability-stack
   npm install
   npm start
   ```

3. **Verify the application:**

   Open your browser and navigate to [http://localhost:3000/](http://localhost:3000/). You should see a "Hello World!" message.

## Exposing Metrics with Prometheus

To expose metrics for Prometheus, follow these steps:

1. **Install Prometheus dependencies:**

   ```bash
   npm install @willsoto/nestjs-prometheus prom-client
   ```

2. **Configure the Prometheus module and register a custom counter:**

   Edit `src/app.module.ts` to include the Prometheus module and define a counter to track how often the hello world endpoint is called:

   ```typescript
   import { Module } from '@nestjs/common';
   import { AppController } from './app.controller';
   import { AppService } from './app.service';
   import { PrometheusModule, makeCounterProvider } from '@willsoto/nestjs-prometheus';

   @Module({
     imports: [PrometheusModule.register({ path: '/metrics' })],
     controllers: [AppController],
     providers: [
       AppService,
       makeCounterProvider({
         name: 'get_hello_calls',
         help: 'Total number of getHello calls',
       }),
     ],
   })
   export class AppModule {}
   ```

3. **Increment the counter in the service:**

   Modify `src/app.service.ts` so that the `getHello()` method increments the counter every time it is called:

   ```typescript
   import { Injectable } from '@nestjs/common';
   import { InjectMetric } from '@willsoto/nestjs-prometheus';
   import { Counter } from 'prom-client';

   @Injectable()
   export class AppService {
     constructor(@InjectMetric('get_hello_calls') public counter: Counter<string>) {}

     getHello(): string {
       this.counter.inc();
       return 'Hello World!';
     }
   }
   ```

4. **Test the metrics endpoint:**

   Restart your application and visit [http://localhost:3000/metrics](http://localhost:3000/metrics). You should see Prometheus metrics including your custom `get_hello_calls` counter. Call the `/` endpoint a few times and observe the counter increment.

## Dockerizing the Infrastructure

To simplify deployment and network configuration, we will dockerize both the NestJS application and the monitoring tools.

### Create a Dockerfile for the NestJS Application

In the root of your project, create a file named `Dockerfile` with the following content:

```dockerfile
# Stage 1: Build the application
FROM node:22-alpine AS builder

WORKDIR /app

# Copy dependency manifests and configuration files
COPY package*.json nest-cli.json tsconfig*.json ./

# Copy the source files
COPY src/ ./src

# Install dependencies and build the app
RUN npm ci && npm run build


# Stage 2: Create the production image
FROM node:22-alpine

WORKDIR /app

# Set the production environment variable
ENV NODE_ENV=production

# Copy production dependencies and built files from the builder stage
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
# Expose the port the app will run on

EXPOSE 3000
# Add a health check
RUN apk add --no-cache curl
HEALTHCHECK --interval=30s --timeout=3s CMD curl -f http://localhost:3000/ || exit 1

# Start the application
CMD ["node", "dist/main.js"]

```

This multi-stage Dockerfile builds the application and then runs the production-ready code.

### Set Up Docker Compose

Create a `docker-compose.yml` file to orchestrate the NestJS app, Prometheus, and Grafana:

```yaml
version: '3.8'

services:
  nestjs-observability-stack:
    build: .
    container_name: nestjs-observability-stack
    ports:
      - "3000:3000"
    # Wait for Prometheus to be available before starting
    depends_on:
      - prometheus
    restart: always

  prometheus:
    image: prom/prometheus:v2.54.1
    container_name: prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    restart: always

  grafana:
    image: grafana/grafana:11.2.2
    container_name: grafana
    ports:
      - "3030:3000"
    restart: always

```

### Configure Prometheus

Create a `prometheus.yml` file in the project root with the following configuration:

```yaml
# Global configuration applies to all scrape jobs.
global:
  scrape_interval: 15s  # How often to scrape targets by default.
  scrape_timeout: 10s   # Timeout before a scrape is declared failed.

scrape_configs:
  - job_name: "nestjs-observability-stack-service"  # Name of the job for identification.
    metrics_path: /metrics  # The endpoint where metrics are exposed.
    static_configs:
      - targets: 
          - "nestjs-observability-stack:3000"  # Target container and port.

```

This tells Prometheus to scrape the metrics endpoint of the NestJS application every 15 seconds.

## Running the Environment

Start all containers using Docker Compose:

```bash
docker compose up -d
```

Wait for all three containers (NestJS app, Prometheus, and Grafana) to initialize.

## Testing and Validation

1. **Verify Application Metrics:**

   - Open [http://localhost:3000/metrics](http://localhost:3000/metrics) to ensure your metrics (including `get_hello_calls`) are exposed.
   - Access the Prometheus UI at [http://localhost:9090/](http://localhost:9090/).

2. **Query Metrics in Prometheus:**

   - In the Prometheus UI, enter `get_hello_calls` in the query bar and click "Execute" to view the current counter value.
   - Hit [http://localhost:3000/](http://localhost:3000/) several times and observe the counter value update.

## Setting Up Grafana Dashboard

1. **Access Grafana:**

   Navigate to [http://localhost:3030/](http://localhost:3030/) and log in using the default credentials `admin/admin`. (You will be prompted to change the password on first login.)

2. **Configure the Prometheus Data Source:**

   - Open the side panel and select **Dashboards** → **Create Dashboard** → **Add visualization** → **Configure a new datasource**.
   - Choose **Prometheus** as the datasource.
   - Set the connection URL to `http://prometheus:9090/` and click **Save & Test**.

3. **Create a Dashboard Visualization:**

   - With the Prometheus datasource configured, create a new dashboard visualization.
   - Select the `get_hello_calls` metric and save the visualization.
   - Now you can monitor how the metric changes over time in Grafana.
