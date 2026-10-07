===================================================================
Containerized Lima VM & GitHub Runners Infrastructure Documentation
===================================================================

Welcome to the documentation suite for the **Lima VM GitHub Runners & Cockpit Infrastructure** workspace.

This infrastructure provisions containerized GitHub Actions self-hosted runners inside a Lima KVM virtual machine, deploys the Cockpit web management console, and handles unprivileged USB serial device passthrough (``/dev/ttyACM*``) for embedded hardware CI/CD testing.

Table of Contents
=================

.. toctree::
   :maxdepth: 2
   :caption: Core Documentation

   
   
   OPERATIONS_AND_TROUBLESHOOTING
   HARDWARE_EXPANSION_GUIDE

.. toctree::
   :maxdepth: 2
   :caption: Technical Reports & Deep Dives

   usb_fault_resolution_report

Quick Reference & Navigation
============================

* **Quick Start & Architecture**: See :doc:`README` for setup steps, playbook CLI flags, and directory structure.
* **Day-2 Operations & Monitoring**: See :doc:`OPERATIONS_AND_TROUBLESHOOTING` for log collection, secret rotation, and troubleshooting workflows.
* **Onboarding New Hardware**: See :doc:`HARDWARE_EXPANSION_GUIDE` for adding new MCU targets and USB debug adapters (FTDI, CP210x, CDC-ACM).
* **USB Resolution Post-Mortem**: See :doc:`usb_fault_resolution_report` for the root-cause analysis on Linux Cgroup device rule ``c 166:* rmw``.

Indices and Tables
==================

* :ref:`genindex`
* :ref:`search`
