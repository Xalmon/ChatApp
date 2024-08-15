git branch -M main
git remote add origin https://github.com/xalmon/$APP_NAME.git
git push -u origin main


#!/bin/bash

# Check if mvn command is available
if ! command -v mvn &> /dev/null; then
    echo "Maven (mvn) could not be found. Please install Maven."
    exit 1
fi

# Check if gh command is available
if ! command -v gh &> /dev/null; then
    echo "GitHub CLI (gh) could not be found. Please install GitHub CLI."
    exit 1
fi

# Prompt for the application name
echo "Enter the name of your Spring Boot application:"
read APP_NAME

# Set the package name
PACKAGE_NAME="com.example.$APP_NAME"

# Create the directory structure
mkdir -p $APP_NAME/.github/workflows
cat <<EOL > $APP_NAME/.github/workflows/build-create-docker-image.yml

name: Java CI with Maven

on:
  push:
    branches: [ "main" ]

jobs:
  test:
    name: Unit Test
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v1
      - name: Set up JDK 18
        uses: actions/setup-java@v1
        with:
          java-version: 18
      - name: Maven Package
        run: mvn -B clean package -DskipTests
      - name: Maven Verify
        run: mvn -B clean verify

  build:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3
      - name: Set up JDK 18
        uses: actions/setup-java@v3
        with:
          java-version: '18'
          distribution: 'temurin'
          cache: maven
      - name: Build with Maven
        run: mvn -B package --file pom.xml

      - name: Set up Node.js
        uses: actions/setup-node@v2
        with:
          node-version: '14'

      - name: Build, tag image
        id: build-image
        run: |
          docker build -t xalmon\\${APP_NAME}:latest .

EOL

mkdir -p $APP_NAME/src/main/java/$PACKAGE_NAME
mkdir -p $APP_NAME/src/main/resources
mkdir -p $APP_NAME/src/test/java/$PACKAGE_NAME

# Create the Spring Boot application file
cat <<EOL > $APP_NAME/src/main/java/$PACKAGE_NAME/${APP_NAME}Application.java
package $PACKAGE_NAME;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class ${APP_NAME}Application {

  public static void main(String[] args) {
    SpringApplication.run(${APP_NAME}Application.class, args);
  }
}
EOL

# Create the application.yml file
cat <<EOL > $APP_NAME/src/main/resources/application.yml
spring:
  profiles:
    active: \${SPRING_PROFILES_ACTIVE:local}

logging:
  level:
    org.springframework.security: DEBUG
EOL

cat <<EOL > $APP_NAME/src/main/resources/application-local.yml
spring:
  data:
    mongodb:
      uri: mongodb://localhost:27017/\${MONGO_DB_NAME:mydatabase}

  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: \${keycloak.server}/realms/\${keycloak.realm}

MAIL_HOST: \${EMAIL_HOST:sandbox.smtp.mailtrap.io}
MAIL_PORT: \${EMAIL_PORT:2525}
MAIL_USERNAME: \${EMAIL_USERNAME}
MAIL_PASSWORD: \${EMAIL_PASSWORD}
MAIL_SENDER: \${EMAIL_SENDER}

FRONTEND_URL: \${FRONTEND_BASE_URL:https://localhost:3000}

keycloak:
  server: http://localhost:8090
  username: admin
  password: admin
  realm:
  client:
  principal_attribute: preferred_username
  enabled:
jwt:
  secret: \${JWT_SECRET}
  expiration: \${JWT_EXPIRATION:3600}

logging:
  level:
    org.springframework.security: DEBUG

springdoc:
  swagger-ui:
    path: '/swagger-ui.html'
    filter: true
    tags-sorter: alpha
EOL

# Verify the file creation
if [ -f "$APP_NAME/src/main/resources/application-local.yml" ]; then
  echo "application-local.yml has been created successfully."
else
  echo "Failed to create application-local.yml."
fi

touch $APP_NAME/src/main/resources/application-dev.yml
touch $APP_NAME/src/main/resources/application-uat.yml
touch $APP_NAME/src/main/resources/application-prod.yml

# Create the test file
cat <<EOL > $APP_NAME/src/test/java/$PACKAGE_NAME/${APP_NAME}ApplicationTests.java
package $PACKAGE_NAME;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

@SpringBootTest
public class ${APP_NAME}ApplicationTests {

  @Test
  public void contextLoads() {
  }

}
EOL

# Create Dockerfile
cat <<EOL > $APP_NAME/Dockerfile
FROM maven:3.8.7 as build
COPY . .
RUN mvn -B clean package -DskipTests

FROM openjdk:17
COPY --from=build ./target/*.jar app.jar
ENTRYPOINT ["java", "-jar", "-Dserver.port=\${PORT}", "-Dspring.profiles.active=\${PROFILE}","app.jar"]
EOL

# Create docker-compose.yml
cat <<EOL > $APP_NAME/docker-compose.yml
version: '3.18'

services:

  mongodb:
    image: mongo:latest
    ports:
      - "27017:27017"
    environment:
      MONGO_INITDB_ROOT_USERNAME: root
      MONGO_INITDB_ROOT_PASSWORD: example

  keycloak:
    image: quay.io/keycloak/keycloak:latest
    command: [ 'start-dev' ]
    ports:
      - "8090:8080"
    environment:
      KEYCLOAK_ADMIN: admin
      KEYCLOAK_ADMIN_PASSWORD: admin

  rabbitmq:
    image: rabbitmq:3.11-management-alpine
    ports:
      - "5672:5672"
      - "15672:15672"
    environment:
      RABBITMQ_DEFAULT_USER: guest
      RABBITMQ_DEFAULT_PASS: guest
      RABBITMQ_DEFAULT_VHOST: /
    volumes:
      - ./rabbitmq-data:/var/lib/rabbitmq

networks:
  local:
    name: local
    driver: bridge
  rabbitmq:
    name: rabbitmq
    driver: bridge
EOL

# Create the pom.xml file (if you're using Maven)
cat <<EOL > $APP_NAME/pom.xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">

         <modelVersion>4.0.0</modelVersion>

  <groupId>$PACKAGE_NAME</groupId>
  <artifactId>$APP_NAME</artifactId>
  <version>0.0.1-SNAPSHOT</version>
  <packaging>jar</packaging>

  <name>$APP_NAME</name>
  <description>Demo project for Spring Boot</description>

  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.0.0</version>
    <relativePath/> <!-- lookup parent from repository -->
  </parent>

  <properties>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    <project.reporting.outputEncoding>UTF-8</project.reporting.outputEncoding>
    <java.version>17</java.version>
  </properties>

  <dependencies>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-web</artifactId>
    </dependency>

    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-test</artifactId>
      <scope>test</scope>
    </dependency>

        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-data-mongodb</artifactId>
        </dependency>

        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-validation</artifactId>
            <version>3.0.0</version>
        </dependency>

        <dependency>
            <groupId>org.modelmapper</groupId>
            <artifactId>modelmapper</artifactId>
            <version>3.1.1</version>
        </dependency>

        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-actuator</artifactId>
        </dependency>

        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-security</artifactId>
        </dependency>

    <dependency>
      <groupId>org.projectlombok</groupId>
      <artifactId>lombok</artifactId>
      <optional>true</optional>
    </dependency>
  </dependencies>

  <build>
    <plugins>
      <plugin>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-maven-plugin</artifactId>
        <configuration>
          <excludes>
            <exclude>
              <groupId>org.projectlombok</groupId>
              <artifactId>lombok</artifactId>
            </exclude>
          </excludes>
        </configuration>
      </plugin>
    </plugins>
  </build>
</project>
EOL

# Change into the application directory
cd $APP_NAME


# Build the project
mvn clean -B verify

# Initialize a Git repository
git init

# Create GitHub repository
gh repo create $APP_NAME --public --source=. --remote=origin

# Add all files to the repository
git add .

# Commit the changes
git commit -m "Initial commit"

# Create and push the main branch
git branch -M main
git push -u origin main

# Give execute permission to the files
chmod +x .

echo "Spring Boot project $APP_NAME has been created and pushed to GitHub successfully."


#!/bin/bash

# Check if mvn command is available
if ! command -v mvn &> /dev/null; then
    echo "Maven (mvn) could not be found. Please install Maven."
    exit 1
fi

# Check if gh command is available
if ! command -v gh &> /dev/null; then
    echo "GitHub CLI (gh) could not be found. Please install GitHub CLI."
    exit 1
fi

# Prompt for the application name
echo "Enter the name of your Spring Boot application:"
read APP_NAME

# Set the package name
PACKAGE_NAME="com.example.$APP_NAME"

# Create the directory structure
mkdir -p $APP_NAME/.github/workflows
cat <<EOL > $APP_NAME/.github/workflows/build-create-docker-image.yml
name: Java CI with Maven

on:
  push:
    branches: [ "main" ]

jobs:
  test:
    name: Unit Test
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v1
      - name: Set up JDK 18
        uses: actions/setup-java@v1
        with:
          java-version: 18
      - name: Maven Package
        run: mvn -B clean package -DskipTests
      - name: Maven Verify
        run: mvn -B clean verify

  build:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3
      - name: Set up JDK 18
        uses: actions/setup-java@v3
        with:
          java-version: '18'
          distribution: 'temurin'
          cache: maven
      - name: Build with Maven
        run: mvn -B package --file pom.xml

      - name: Set up Node.js
        uses: actions/setup-node@v2
        with:
          node-version: '14'

      - name: Build, tag image
        id: build-image
        run: |
          docker build -t xalmon\\${APP_NAME}:latest .

EOL

mkdir -p $APP_NAME/src/main/java/$PACKAGE_NAME
mkdir -p $APP_NAME/src/main/resources
mkdir -p $APP_NAME/src/test/java/$PACKAGE_NAME

# Create the Spring Boot application file
cat <<EOL > $APP_NAME/src/main/java/$PACKAGE_NAME/${APP_NAME}Application.java
package $PACKAGE_NAME;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class ${APP_NAME}Application {

  public static void main(String[] args) {
    SpringApplication.run(${APP_NAME}Application.class, args);
  }
}
EOL

# Create the application.yml file
cat <<EOL > $APP_NAME/src/main/resources/application.yml
spring:
  profiles:
    active: \${SPRING_PROFILES_ACTIVE:local}

logging:
  level:
    org.springframework.security: DEBUG
EOL

cat <<EOL > $APP_NAME/src/main/resources/application-local.yml
spring:
  data:
    mongodb:
      uri: mongodb://localhost:27017/\${MONGO_DB_NAME:mydatabase}

  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: \${keycloak.server}/realms/\${keycloak.realm}

MAIL_HOST: \${EMAIL_HOST:sandbox.smtp.mailtrap.io}
MAIL_PORT: \${EMAIL_PORT:2525}
MAIL_USERNAME: \${EMAIL_USERNAME}
MAIL_PASSWORD: \${EMAIL_PASSWORD}
MAIL_SENDER: \${EMAIL_SENDER}

FRONTEND_URL: \${FRONTEND_BASE_URL:https://localhost:3000}

keycloak:
  server: http://localhost:8090
  username: admin
  password: admin
  realm:
  client:
  principal_attribute: preferred_username
  enabled:
jwt:
  secret: \${JWT_SECRET}
  expiration: \${JWT_EXPIRATION:3600}

logging:
  level:
    org.springframework.security: DEBUG

springdoc:
  swagger-ui:
    path: '/swagger-ui.html'
    filter: true
    tags-sorter: alpha
EOL

# Verify the file creation
if [ -f "$APP_NAME/src/main/resources/application-local.yml" ]; then
  echo "application-local.yml has been created successfully."
else
  echo "Failed to create application-local.yml."
fi

touch $APP_NAME/src/main/resources/application-dev.yml
touch $APP_NAME/src/main/resources/application-uat.yml
touch $APP_NAME/src/main/resources/application-prod.yml

# Create the test file
cat <<EOL > $APP_NAME/src/test/java/$PACKAGE_NAME/${APP_NAME}ApplicationTests.java
package $PACKAGE_NAME;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

@SpringBootTest
public class ${APP_NAME}ApplicationTests {

  @Test
  public void contextLoads() {
  }

}
EOL


# Create Dockerfile
cat <<EOL > $APP_NAME/Dockerfile
FROM maven:3.8.7 as build
COPY . .
RUN mvn -B clean package -DskipTests

FROM openjdk:17
COPY --from=build ./target/*.jar app.jar
ENTRYPOINT ["java", "-jar", "-Dserver.port=\${PORT}", "-Dspring.profiles.active=\${PROFILE}","app.jar"]
EOL

# Create docker-compose.yml
cat <<EOL > $APP_NAME/docker-compose.yml
version: '3.18'

services:

  mongodb:
    image: mongo:latest
    ports:
      - "27017:27017"
    environment:
      MONGO_INITDB_ROOT_USERNAME: root
      MONGO_INITDB_ROOT_PASSWORD: example

  keycloak:
    image: quay.io/keycloak/keycloak:latest
    command: [ 'start-dev' ]
    ports:
      - "8090:8080"
    environment:
      KEYCLOAK_ADMIN: admin
      KEYCLOAK_ADMIN_PASSWORD: admin

  rabbitmq:
    image: rabbitmq:3.11-management-alpine
    ports:
      - "5672:5672"
      - "15672:15672"
    environment:
      RABBITMQ_DEFAULT_USER: guest
      RABBITMQ_DEFAULT_PASS: guest
      RABBITMQ_DEFAULT_VHOST: /
    volumes:
      - ./rabbitmq-data:/var/lib/rabbitmq

networks:
  local:
    name: local
    driver: bridge
  rabbitmq:
    name: rabbitmq
    driver: bridge
EOL

# Create the pom.xml file (if you're using Maven)
cat <<EOL > $APP_NAME/pom.xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">

         <modelVersion>4.0.0</modelVersion>

  <groupId>$PACKAGE_NAME</groupId>
  <artifactId>$APP_NAME</artifactId>
  <version>0.0.1-SNAPSHOT</version>
  <packaging>jar</packaging>

  <name>$APP_NAME</name>
  <description>Demo project for Spring Boot</description>

  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.0.0</version>
    <relativePath/> <!-- lookup parent from repository -->
  </parent>

  <properties>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    <project.reporting.outputEncoding>UTF-8</project.reporting.outputEncoding>
    <java.version>17</java.version>
  </properties>

  <dependencies>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-web</artifactId>
    </dependency>

    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-test</artifactId>
      <scope>test</scope>
    </dependency>

        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-data-mongodb</artifactId>
        </dependency>

        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-validation</artifactId>
            <version>3.0.0</version>
        </dependency>

        <dependency>
            <groupId>org.modelmapper</groupId>
            <artifactId>modelmapper</artifactId>
            <version>3.1.1</version>
        </dependency>

        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-actuator</artifactId>
        </dependency>

        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-security</artifactId>
        </dependency>

    <dependency>
      <groupId>org.projectlombok</groupId>
      <artifactId>lombok</artifactId>
      <optional>true</optional>
    </dependency>
  </dependencies>

  <build>
    <plugins>
      <plugin>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-maven-plugin</artifactId>
        <configuration>
          <excludes>
            <exclude>
              <groupId>org.projectlombok</groupId>
              <artifactId>lombok</artifactId>
            </exclude>
          </excludes>
        </configuration>
      </plugin>
    </plugins>
  </build>
</project>
EOL

# Change into the application directory
cd $APP_NAME

# Build the project
mvn clean -B verify

# Initialize a Git repository
git init

# Create GitHub repository
gh repo create $APP_NAME --public --source=. --remote=origin

# Add all files to the repository
git add .

# Commit the changes
git commit -m "Initial commit"

# Create and push the main branch
git branch -M main
git push -u origin main

# Give execute permission to the files
chmod +x .

echo "Spring Boot project $APP_NAME has been created and pushed to GitHub successfully."
#!/bin/bash

# Check if mvn command is available
if ! command -v mvn &> /dev/null; then
    echo "Maven (mvn) could not be found. Please install Maven."
    exit 1
fi

# Check if gh command is available
if ! command -v gh &> /dev/null; then
    echo "GitHub CLI (gh) could not be found. Please install GitHub CLI."
    exit 1
fi

# Prompt for the application name
echo "Enter the name of your Spring Boot application:"
read APP_NAME

# Set the package name
PACKAGE_NAME="com.example.$APP_NAME"

# Create the directory structure
mkdir -p $APP_NAME/.github/workflows
cat <<EOL > $APP_NAME/.github/workflows/build-create-docker-image.yml
name: Java CI with Maven

on:
  push:
    branches: [ "main" ]

jobs:
  test:
    name: Unit Test
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v1
      - name: Set up JDK 18
        uses: actions/setup-java@v1
        with:
          java-version: 18
      - name: Maven Package
        run: mvn -B clean package -DskipTests
      - name: Maven Verify
        run: mvn -B clean verify

  build:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3
      - name: Set up JDK 18
        uses: actions/setup-java@v3
        with:
          java-version: '18'
          distribution: 'temurin'
          cache: maven
      - name: Build with Maven
        run: mvn -B package --file pom.xml

      - name: Set up Node.js
        uses: actions/setup-node@v2
        with:
          node-version: '14'

      - name: Build, tag image
        id: build-image
        run: |
          docker build -t xalmon\\${APP_NAME}:latest .

EOL

mkdir -p $APP_NAME/src/main/java/$PACKAGE_NAME
mkdir -p $APP_NAME/src/main/resources
mkdir -p $APP_NAME/src/test/java/$PACKAGE_NAME

# Create the Spring Boot application file
cat <<EOL > $APP_NAME/src/main/java/$PACKAGE_NAME/${APP_NAME}Application.java
package $PACKAGE_NAME;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class ${APP_NAME}Application {

  public static void main(String[] args) {
    SpringApplication.run(${APP_NAME}Application.class, args);
  }
}
EOL

# Create the application.yml file
cat <<EOL > $APP_NAME/src/main/resources/application.yml
spring:
  profiles:
    active: \${SPRING_PROFILES_ACTIVE:local}

logging:
  level:
    org.springframework.security: DEBUG
EOL

cat <<EOL > $APP_NAME/src/main/resources/application-local.yml
spring:
  data:
    mongodb:
      uri: mongodb://localhost:27017/\${MONGO_DB_NAME:mydatabase}

  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: \${keycloak.server}/realms/\${keycloak.realm}

MAIL_HOST: \${EMAIL_HOST:sandbox.smtp.mailtrap.io}
MAIL_PORT: \${EMAIL_PORT:2525}
MAIL_USERNAME: \${EMAIL_USERNAME}
MAIL_PASSWORD: \${EMAIL_PASSWORD}
MAIL_SENDER: \${EMAIL_SENDER}

FRONTEND_URL: \${FRONTEND_BASE_URL:https://localhost:3000}

keycloak:
  server: http://localhost:8090
  username: admin
  password: admin
  realm:
  client:
  principal_attribute: preferred_username
  enabled:
jwt:
  secret: \${JWT_SECRET}
  expiration: \${JWT_EXPIRATION:3600}

logging:
  level:
    org.springframework.security: DEBUG

springdoc:
  swagger-ui:
    path: '/swagger-ui.html'
    filter: true
    tags-sorter: alpha
EOL

# Verify the file creation
if [ -f "$APP_NAME/src/main/resources/application-local.yml" ]; then
  echo "application-local.yml has been created successfully."
else
  echo "Failed to create application-local.yml."
fi

touch $APP_NAME/src/main/resources/application-dev.yml
touch $APP_NAME/src/main/resources/application-uat.yml
touch $APP_NAME/src/main/resources/application-prod.yml

# Create the test file
cat <<EOL > $APP_NAME/src/test/java/$PACKAGE_NAME/${APP_NAME}ApplicationTests.java
package $PACKAGE_NAME;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

@SpringBootTest
public class ${APP_NAME}ApplicationTests {

  @Test
  public void contextLoads() {
  }

}
EOL

# Create Dockerfile
cat <<EOL > $APP_NAME/Dockerfile
FROM maven:3.8.7 as build
COPY . .
RUN mvn -B clean package -DskipTests

FROM openjdk:17
COPY --from=build ./target/*.jar app.jar
ENTRYPOINT ["java", "-jar", "-Dserver.port=\${PORT}", "-Dspring.profiles.active=\${PROFILE}","app.jar"]
EOL

# Create docker-compose.yml
cat <<EOL > $APP_NAME/docker-compose.yml
version: '3.18'

services:

  mongodb:
    image: mongo:latest
    ports:
      - "27017:27017"
    environment:
      MONGO_INITDB_ROOT_USERNAME: root
      MONGO_INITDB_ROOT_PASSWORD: example

  keycloak:
    image: quay.io/keycloak/keycloak:latest
    command: [ 'start-dev' ]
    ports:
      - "8090:8080"
    environment:
      KEYCLOAK_ADMIN: admin
      KEYCLOAK_ADMIN_PASSWORD: admin

  rabbitmq:
    image: rabbitmq:3.11-management-alpine
    ports:
      - "5672:5672"
      - "15672:15672"
    environment:
      RABBITMQ_DEFAULT_USER: guest
      RABBITMQ_DEFAULT_PASS: guest
      RABBITMQ_DEFAULT_VHOST: /
    volumes:
      - ./rabbitmq-data:/var/lib/rabbitmq

networks:
  local:
    name: local
    driver: bridge
  rabbitmq:
    name: rabbitmq
    driver: bridge
EOL

# Create the pom.xml file (if you're using Maven)
  cat <<EOL > $APP_NAME/pom.xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">

         <modelVersion>4.0.0</modelVersion>

  <groupId>$PACKAGE_NAME</groupId>
  <artifactId>$APP_NAME</artifactId>
  <version>0.0.1-SNAPSHOT</version>
  <packaging>jar</packaging>

  <name>$APP_NAME</name>
  <description>Demo project for Spring Boot</description>

  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.0.0</version>
    <relativePath/> <!-- lookup parent from repository -->
  </parent>

  <properties>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    <project.reporting.outputEncoding>UTF-8</project.reporting.outputEncoding>
    <java.version>17</java.version>
  </properties>

  <dependencies>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-web</artifactId>
    </dependency>

    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-test</artifactId>
      <scope>test</scope>
    </dependency>

        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-data-mongodb</artifactId>
        </dependency>

        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-validation</artifactId>
            <version>3.0.0</version>
        </dependency>

        <dependency>
            <groupId>org.modelmapper</groupId>
            <artifactId>modelmapper</artifactId>
            <version>3.1.1</version>
        </dependency>

        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-actuator</artifactId>
        </dependency>

        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-security</artifactId>
        </dependency>

    <dependency>
      <groupId>org.projectlombok</groupId>
      <artifactId>lombok</artifactId>
      <optional>true</optional>
    </dependency>
  </dependencies>
