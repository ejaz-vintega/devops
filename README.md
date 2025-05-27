# DevOps Utilities

## Overview

This repository provides a collection of DevOps scripts and code snippets designed to automate and streamline various development and operational tasks. Our goal is to offer robust and easy-to-use tools for common server setup and management processes.

## Scripts

This section details the available scripts, their functionalities, and how to use them.

### `server-setup.sh`

This interactive script automates the initial setup of a new server environment, specifically tailored for Ubuntu (20.04+ or compatible Debian-based) systems. It guides users through a series of prompts to customize the installation and configuration of various components.

**Key Functionalities:**

*   **Interactive Configuration:** The script asks targeted questions to determine which software and settings are required for your specific use case.
*   **Software Installation:**
    *   **Node.js:** Allows selection of specific versions to match project requirements.
    *   **MongoDB:** Installs the NoSQL database.
    *   **Redis Cache:** Sets up an in-memory data structure store.
    *   **Nginx:** Installs and configures a high-performance web server.
    *   **SSL with Certbot:** Automates the process of obtaining and renewing SSL certificates.
    *   **Git:** Installs the version control system.
    *   **PM2:** Deploys a production-grade process manager for Node.js applications.
*   **Project Deployment:** Facilitates cloning a project repository from a Git source.
*   **Nginx as Reverse Proxy:** Configures Nginx to act as a reverse proxy for the deployed application.
*   **Optional Components:** Most installations are optional and can be skipped if they are already installed or not needed.

### `test_server_setup.sh`

This script provides an automated testing framework for the `server-setup.sh` script. Its primary purpose is to ensure the reliability and correctness of the main setup script.

**Testing Methodology:**

*   **Mock Commands:** Utilizes a mock command system to simulate a real server environment. This enables thorough testing of the script's logic without making actual system modifications, thus preventing unintended side effects.
*   **Scenario-Based Execution:** Executes `server-setup.sh` with a diverse range of inputs and under various simulated conditions to verify its behavior across different scenarios.
*   **Verification Checks:** Performs critical checks, including:
    *   Validation of user inputs (e.g., handling invalid domain names, unsupported Node.js versions).
    *   Correctness of installation sequences based on user selections.
    *   Accurate generation of Nginx configuration files tailored to the provided inputs.

## Usage

### Using `server-setup.sh`

To use the `server-setup.sh` script:

1.  **Clone the Repository:**
    ```bash
    git clone <repository-url>
    ```
    (Replace `<repository-url>` with the actual URL of this repository)
2.  **Navigate to Directory:**
    ```bash
    cd <repository-directory>
    ```
    (Replace `<repository-directory>` with the name of the cloned directory)
3.  **Make Executable:**
    ```bash
    chmod +x server-setup.sh
    ```
4.  **Run the Script:**
    ```bash
    ./server-setup.sh
    ```
5.  **Follow Prompts:** Answer the on-screen questions to configure your server setup.

## Prerequisites

Before running the `server-setup.sh` script, ensure the following conditions are met:

*   **Operating System:** Ubuntu 20.04+ or a compatible Debian-based distribution.
*   **SSH Key for Git Deployment:**
    *   An SSH key pair must be generated. The private key should be located at `~/.ssh/id_rsa`.
    *   Secure the private key by restricting its permissions: `sudo chmod 600 ~/.ssh/id_rsa`.
*   **Domain Name:** A domain name must be configured to point to the server's public IP address. This is crucial for SSL certificate issuance via Certbot.

## Testing

To maintain the integrity of the `server-setup.sh` script, especially after modifications, it is essential to run the automated tests using `test_server_setup.sh`.

**How to Run Tests:**

The `test_server_setup.sh` script is designed to be run directly from the command line:

1.  Ensure the script has execute permissions:
    ```bash
    chmod +x test_server_setup.sh
    ```
2.  Execute the script:
    ```bash
    ./test_server_setup.sh
    ```
    Alternatively, you can run it using:
    ```bash
    bash test_server_setup.sh
    ```

It is highly recommended to run these tests whenever changes are made to `server-setup.sh` to detect and address potential issues or regressions promptly.
