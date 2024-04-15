## Table of Contents

- [Introduction](#introduction)
- [Description](#description)
- [Automatic Package Builder](#automatic-package-builder)
- [Automatic Package Updater](#automatic-package-updater)
- [Code Linters](#code-linters)
- [Modules and Helpers](#modules-and-helpers)
- [Chocolatey Templates](#chocolatey-templates)


## Introduction

This is a sanitized version of Chocolatey package automations used in a presentation at XGM 2024.

## Description
This repository has several different sections for different automations covered in the package management presentation at XGM 2024. This includes:
* Automatic Package Builder ADO Pipeline
* NeverEvergreen Automatic Package Updater ADO Pipeline
* Code linting using PSScriptAnalyzer and Pester
* Backing scripts, modules, and functions
* Basic Chocolatey templates for different binary types

Generally speaking, anything enclosed in <> will need to be replaced with values pertinent to your own deployment. I'm not going to pretend that this is perfect, as it is still a work in progress, but it is functional in our environment!

## Automatic Package Builder
This contains an Azure DevOps pipeline and the backing scripts that will automatically pack and push any necessary Chocolatey packages in your repository.

## Automatic Package Updater
This contains an Azure DevOps pipeline and the backing scripts that uses Evergreen, Nevergreen, and custom injected modules to automatically update supported Chocolatey packages. It will go through a list of packages to filter down the returned binaries to match the desired parameters, and then determine if the Chocolatey package that uses it needs to be updated. If it does, it will automatically create a new git branch, modify the package code, then create a pull request with auto merge enabled. It will also create ADO work items and link them to the pull request.

## Code Linters
This contains code linting pipelines and GH Actions using PSScriptAnalyzer and Pester. Pester code specifically is different from the usual method since it needs to be able to target multiple paths using the same test file. This is accomplished using nested loops that identify the files to scan for each test. It also publishes the results in a way that allows for code annotations on the affected lines.

## Modules and Helpers
This contains all the modules and helper scripts that are used in different pipelines and processes.

## Chocolatey Templates
This is a collection of basic Chocolatey package templates that can be easily adapted to different binaries. It is mostly the templated code you get when running 'choco new' but with a few changes/additions.
