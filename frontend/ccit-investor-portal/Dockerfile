FROM node:20-alpine AS build

WORKDIR /app
# Copy package files for better Docker layer caching
COPY package*.json ./
RUN npm ci

# Only copy source files (respects .dockerignore)
COPY . .
RUN npm run build

FROM nginx:alpine
# Copy the built application
COPY --from=build /app/dist /usr/share/nginx/html
# Copy nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
