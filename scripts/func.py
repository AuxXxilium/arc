# -*- coding: utf-8 -*-
#
# Copyright (C) 2023 AuxXxilium <https://github.com/AuxXxilium> and Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

import os, sys, glob, json, yaml, click, shutil, tarfile, kmodule, requests
from openpyxl import Workbook


@click.group()
def cli():
    """
    The CLI is a commands to Arc.
    """
    pass


@cli.command()
@click.option("-w", "--workpath", type=str, required=True, help="The workpath of Arc.")
@click.option("-j", "--jsonpath", type=str, required=True, help="The output path of jsonfile.")
def getmodels(workpath, jsonpath):

    models = {}
    with open("{}/mnt/p3/configs/platforms.yml".format(workpath), "r") as f:
        P_data = yaml.safe_load(f)
        P_platforms = P_data.get("platforms", [])
        for P in P_platforms:
            productvers = {}
            for V in P_platforms[P]["productvers"]:
                if P == "epyc7002":
                    productvers[V] = P_platforms[P]["productvers"][V].get("productver", "") + "-" + P_platforms[P]["productvers"][V].get("kver", "")
                else:
                    productvers[V] = P_platforms[P]["productvers"][V].get("kver", "")
            models[P] = {"productvers": productvers, "models": []}

    req = requests.get("https://autoupdate.synology.com/os/v2")
    req.encoding = "utf-8"
    data = json.loads(req.text)

    for I in data["channel"]["item"]:
        if not I["title"].startswith("DSM"):
            continue
        for J in I["model"]:
            arch = J["mUnique"].split("_")[1].lower()
            name = J["mLink"].split("/")[-1].split("_")[1].replace("%2B", "+")
            if arch not in models.keys():
                continue
            if name in (A for B in models for A in models[B]["models"]):
                continue
            models[arch]["models"].append(name)

    if jsonpath:
        with open(jsonpath, "w") as f:
            json.dump(models, f, indent=4, ensure_ascii=False)


@cli.command()
@click.option("-w", "--workpath", type=str, required=True, help="The workpath of Arc.")
@click.option("-j", "--jsonpath", type=str, required=True, help="The output path of jsonfile.")
def getaddons(workpath, jsonpath):
    # Read the manifest.yml file
    AS = glob.glob("{}/mnt/p3/addons/*/manifest.yml".format(workpath))
    AS.sort()
    addons = {}
    for A in AS:
        with open(A, "r") as file:
            A_data = yaml.safe_load(file)
            A_name = A_data.get("name", "")
            A_system = A_data.get("system", False)
            A_description = A_data.get("description", "")
            addons[A_name] = {"system": A_system, "description": A_description}
    if jsonpath:
        with open(jsonpath, "w") as f:
            json.dump(addons, f, indent=4, ensure_ascii=False)


@cli.command()
@click.option("-w", "--workpath", type=str, required=True, help="The workpath of Arc.")
@click.option("-j", "--jsonpath", type=str, required=True, help="The output path of jsonfile.")
def getmodules(workpath, jsonpath):
    # Read the module files
    MS = glob.glob("{}/mnt/p3/modules/*.tgz".format(workpath))
    MS.sort()
    modules = {}
    TMP_PATH = "/tmp/modules"
    if os.path.exists(TMP_PATH):
        shutil.rmtree(TMP_PATH)
    for M in MS:
        M_name = os.path.splitext(os.path.basename(M))[0]
        M_modules = {}
        # Extract the module
        os.makedirs(TMP_PATH)
        with tarfile.open(M, "r") as tar:
            tar.extractall(TMP_PATH)
        # Traverse the extracted files
        KS = glob.glob("{}/*.ko".format(TMP_PATH))
        KS.sort()
        for K in KS:
            K_name = os.path.splitext(os.path.basename(K))[0]
            K_info = kmodule.modinfo(K, basedir=os.path.dirname(K), kernel=None)[0]
            K_description = K_info.get("description", "")
            K_depends = K_info.get("depends", "")
            M_modules[K_name] = {"description": K_description, "depends": K_depends}
        modules[M_name] = M_modules
        if os.path.exists(TMP_PATH):
            shutil.rmtree(TMP_PATH)
    if jsonpath:
        with open(jsonpath, "w") as file:
            json.dump(modules, file, indent=4, ensure_ascii=False)


if __name__ == "__main__":
    cli()
