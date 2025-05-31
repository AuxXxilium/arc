# -*- coding: utf-8 -*-
#
# Copyright (C) 2025 AuxXxilium <https://github.com/AuxXxilium>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

import os, re, sys, glob, json, yaml, click, shutil, tarfile, kmodule, requests, urllib3
from requests.adapters import HTTPAdapter
from requests.packages.urllib3.util.retry import Retry  # type: ignore
from openpyxl import Workbook

@click.group()
def cli():
    """
    The CLI is a commands to ARC.
    """
    pass


@cli.command()
@click.option("-w", "--workpath", type=str, required=True, help="The workpath of ARC.")
@click.option("-j", "--jsonpath", type=str, required=True, help="The output path of jsonfile.")
def getmodels(workpath, jsonpath):
    models = {}
    platforms_yml = os.path.join(workpath, "mnt", "p3", "configs", "platforms.yml")
    with open(platforms_yml, "r") as f:
        P_data = yaml.safe_load(f)
        P_platforms = P_data.get("platforms", [])
        for P in P_platforms:
            productvers = {}
            for V in P_platforms[P]["productvers"]:
                kpre = P_platforms[P]["productvers"][V].get("kpre", "")
                kver = P_platforms[P]["productvers"][V].get("kver", "")
                productvers[V] = f"{kpre}-{kver}" if kpre else kver
            models[P] = {"productvers": productvers, "models": []}

    adapter = HTTPAdapter(max_retries=Retry(total=3, backoff_factor=1, status_forcelist=[500, 502, 503, 504]))
    session = requests.Session()
    session.mount("http://", adapter)
    session.mount("https://", adapter)
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
    
    try:
        url = "http://update7.synology.com/autoupdate/genRSS.php?include_beta=1"
        req = session.get(url, timeout=10, verify=False)
        req.encoding = "utf-8"
        p = re.compile(r"<mUnique>(.*?)</mUnique>.*?<mLink>(.*?)</mLink>", re.MULTILINE | re.DOTALL)
        data = p.findall(req.text)
    except Exception as e:
        click.echo(f"Error: {e}")
        return

    for item in data:
        if not "DSM" in item[1]:
            continue
        arch = item[0].split("_")[1]
        name = item[1].split("/")[-1].split("_")[1].replace("%2B", "+")
        if arch not in models:
            continue
        if name in (A for B in models for A in models[B]["models"]):
            continue
        models[arch]["models"].append(name)

    if jsonpath:
        with open(jsonpath, "w") as f:
            json.dump(models, f, indent=4, ensure_ascii=False)


@cli.command()
@click.option("-w", "--workpath", type=str, required=True, help="The workpath of ARC.")
@click.option("-j", "--jsonpath", type=str, required=True, help="The output path of jsonfile.")
def getpats(workpath, jsonpath):
    # Path to your data.yml file (adjust as needed)
    data_yml_path = os.path.join(workpath, "mnt", "p3", "configs", "data.yml")
    with open(data_yml_path, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f)

    pats = {}
    for platform, models in data.items():
        for model, versions in models.items():
            if model not in pats:
                pats[model] = {}
            for version, info in versions.items():
                url = info.get("url", "")
                checksum = info.get("hash", "")
                pats[model][version] = {
                    "url": url,
                    "sum": checksum
                }

    if jsonpath:
        with open(jsonpath, "w", encoding="utf-8") as f:
            json.dump(pats, f, indent=4, ensure_ascii=False)

@cli.command()
@click.option("-w", "--workpath", type=str, required=True, help="The workpath of ARC.")
@click.option("-j", "--jsonpath", type=str, required=True, help="The output path of jsonfile.")
def getaddons(workpath, jsonpath):
    AS = glob.glob(os.path.join(workpath, "mnt", "p3", "addons", "*", "manifest.yml"))
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
@click.option("-w", "--workpath", type=str, required=True, help="The workpath of ARC.")
@click.option("-j", "--jsonpath", type=str, required=True, help="The output path of jsonfile.")
def getmodules(workpath, jsonpath):
    MS = glob.glob(os.path.join(workpath, "mnt", "p3", "modules", "*.tgz"))
    MS.sort()
    modules = {}
    TMP_PATH = "/tmp/modules"
    if os.path.exists(TMP_PATH):
        shutil.rmtree(TMP_PATH)
    for M in MS:
        M_name = os.path.splitext(os.path.basename(M))[0]
        M_modules = {}
        os.makedirs(TMP_PATH)
        with tarfile.open(M, "r") as tar:
            tar.extractall(TMP_PATH)
        KS = glob.glob(os.path.join(TMP_PATH, "*.ko"))
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