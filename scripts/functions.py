# -*- coding: utf-8 -*-
#
# Copyright (C) 2025 AuxXxilium <https://github.com/AuxXxilium>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

import os, click

WORK_PATH = os.path.abspath(os.path.dirname(__file__))


@click.group()
def cli():
    """
    The CLI is a commands to Arc.
    """
    pass


def mutually_exclusive_options(ctx, param, value):
    other_option = "file" if param.name == "data" else "data"
    if value is not None and ctx.params.get(other_option) is not None:
        raise click.UsageError(f"Illegal usage: `{param.name}` is mutually exclusive with `{other_option}`.")
    return value


def validate_required_param(ctx, param, value):
    if not value and "file" not in ctx.params and "data" not in ctx.params:
        raise click.MissingParameter(param_decls=[param.name])
    return value

def __fullversion(ver):
    out = ver
    arr = ver.split('-')
    if len(arr) > 0:
        a = arr[0].split('.')[0] if len(arr[0].split('.')) > 0 else '0'
        b = arr[0].split('.')[1] if len(arr[0].split('.')) > 1 else '0'
        c = arr[0].split('.')[2] if len(arr[0].split('.')) > 2 else '0'
        d = arr[1] if len(arr) > 1 else '00000'
        e = arr[2] if len(arr) > 2 else '0'
        out = '{}.{}.{}-{}-{}'.format(a,b,c,d,e)
    return out

@cli.command()
@click.option("-p", "--platforms", type=str, help="The platforms of Syno.")
def getmodels(platforms=None):
    """
    Get Syno Models.
    """
    import re, json, requests, urllib3
    from requests.adapters import HTTPAdapter
    from requests.packages.urllib3.util.retry import Retry  # type: ignore

    adapter = HTTPAdapter(max_retries=Retry(total=3, backoff_factor=1, status_forcelist=[500, 502, 503, 504]))
    session = requests.Session()
    session.mount("http://", adapter)
    session.mount("https://", adapter)
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

    PS = platforms.lower().replace(",", " ").split() if platforms else []

    models = []
    try:
        url = "http://update7.synology.com/autoupdate/genRSS.php?include_beta=1"
        #url = "https://update7.synology.com/autoupdate/genRSS.php?include_beta=1"

        req = session.get(url, timeout=10, verify=False)
        req.encoding = "utf-8"
        p = re.compile(r"<mUnique>(.*?)</mUnique>.*?<mLink>(.*?)</mLink>", re.MULTILINE | re.DOTALL)

        data = p.findall(req.text)
        for item in data:
            if not "DSM" in item[1]:
                continue
            arch = item[0].split("_")[1]
            name = item[1].split("/")[-1].split("_")[1].replace("%2B", "+")
            if PS and arch.lower() not in PS:
                continue
            if not any(m["name"] == name for m in models):
                models.append({"name": name, "arch": arch})

        models.sort(key=lambda k: (k["arch"], k["name"]))

    except Exception as e:
        # click.echo(f"Error: {e}")
        pass

    print(json.dumps(models, indent=4))

@cli.command()
@click.option("-m", "--model", type=str, required=True, help="The model of Syno.")
@click.option("-v", "--version", type=str, required=True, help="The version of Syno.")
def getpats4mv(model, version):
    import json, requests, urllib3
    from requests.adapters import HTTPAdapter
    from requests.packages.urllib3.util.retry import Retry  # type: ignore

    adapter = HTTPAdapter(max_retries=Retry(total=3, backoff_factor=1, status_forcelist=[500, 502, 503, 504]))
    session = requests.Session()
    session.mount("http://", adapter)
    session.mount("https://", adapter)
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

    pats = {}
    try:
        urlInfo = "https://www.synology.com/api/support/findDownloadInfo?lang=en-us"
        urlSteps = "https://www.synology.com/api/support/findUpgradeSteps?"
        #urlInfo = "https://www.synology.cn/api/support/findDownloadInfo?lang=zh-cn"
        #urlSteps = "https://www.synology.cn/api/support/findUpgradeSteps?"

        major = f"&major={version.split('.')[0]}" if len(version.split('.')) > 0 else ""
        minor = f"&minor={version.split('.')[1]}" if len(version.split('.')) > 1 else ""
        req = session.get(f"{urlInfo}&product={model.replace('+', '%2B')}{major}{minor}", timeout=10, verify=False)
        req.encoding = "utf-8"
        data = json.loads(req.text)

        build_ver = data['info']['system']['detail'][0]['items'][0]['build_ver']
        build_num = data['info']['system']['detail'][0]['items'][0]['build_num']
        buildnano = data['info']['system']['detail'][0]['items'][0]['nano']
        V = __fullversion(f"{build_ver}-{build_num}-{buildnano}")
        if V not in pats:
            pats[V] = {
                'url': data['info']['system']['detail'][0]['items'][0]['files'][0]['url'].split('?')[0],
                'sum': data['info']['system']['detail'][0]['items'][0]['files'][0]['checksum']
            }

        from_ver = min(I['build'] for I in data['info']['pubVers'])

        for I in data['info']['productVers']:
            if not I['version'].startswith(version):
                continue
            if not major or not minor:
                majorTmp = f"&major={I['version'].split('.')[0]}" if len(I['version'].split('.')) > 0 else ""
                minorTmp = f"&minor={I['version'].split('.')[1]}" if len(I['version'].split('.')) > 1 else ""
                reqTmp = session.get(f"{urlInfo}&product={model.replace('+', '%2B')}{majorTmp}{minorTmp}", timeout=10, verify=False)
                reqTmp.encoding = "utf-8"
                dataTmp = json.loads(reqTmp.text)

                build_ver = dataTmp['info']['system']['detail'][0]['items'][0]['build_ver']
                build_num = dataTmp['info']['system']['detail'][0]['items'][0]['build_num']
                buildnano = dataTmp['info']['system']['detail'][0]['items'][0]['nano']
                V = __fullversion(f"{build_ver}-{build_num}-{buildnano}")
                if V not in pats:
                    pats[V] = {
                        'url': dataTmp['info']['system']['detail'][0]['items'][0]['files'][0]['url'].split('?')[0],
                        'sum': dataTmp['info']['system']['detail'][0]['items'][0]['files'][0]['checksum']
                    }

            for J in I['versions']:
                to_ver = J['build']
                reqSteps = session.get(f"{urlSteps}&product={model.replace('+', '%2B')}&from_ver={from_ver}&to_ver={to_ver}", timeout=10, verify=False)
                if reqSteps.status_code != 200:
                    continue
                reqSteps.encoding = "utf-8"
                dataSteps = json.loads(reqSteps.text)
                for S in dataSteps['upgrade_steps']:
                    if not S.get('full_patch') or not S['build_ver'].startswith(version):
                        continue
                    V = __fullversion(f"{S['build_ver']}-{S['build_num']}-{S['nano']}")
                    if V not in pats:
                        pats[V] = {
                            'url': S['files'][0]['url'].split('?')[0],
                            'sum': S['files'][0]['checksum']
                        }
    except Exception as e:
        # click.echo(f"Error: {e}")
        pass

    pats = {k: pats[k] for k in sorted(pats.keys(), reverse=True)}
    print(json.dumps(pats, indent=4))


@cli.command()
@click.option("-p", "--models", type=str, help="The models of Syno.")
def getpats(models=None):
    import re, json, requests, urllib3
    from bs4 import BeautifulSoup
    from requests.adapters import HTTPAdapter
    from requests.packages.urllib3.util.retry import Retry  # type: ignore

    adapter = HTTPAdapter(max_retries=Retry(total=3, backoff_factor=1, status_forcelist=[500, 502, 503, 504]))
    session = requests.Session()
    session.mount("http://", adapter)
    session.mount("https://", adapter)
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

    MS = models.lower().replace(",", " ").split() if models else []

    pats = {}
    try:
        req = session.get('https://archive.synology.com/download/Os/DSM', timeout=10, verify=False)
        req.encoding = 'utf-8'
        bs = BeautifulSoup(req.text, 'html.parser')
        p = re.compile(r"(.*?)-(.*?)", re.MULTILINE | re.DOTALL)
        l = bs.find_all('a', string=p)
        for i in l:
            ver = i.attrs['href'].split('/')[-1]
            if not ver.startswith('7'):
                continue
            req = session.get(f'https://archive.synology.com{i.attrs["href"]}', timeout=10, verify=False)
            req.encoding = 'utf-8'
            bs = BeautifulSoup(req.text, 'html.parser')
            p = re.compile(r"DSM_(.*?)_(.*?).pat", re.MULTILINE | re.DOTALL)
            data = bs.find_all('a', string=p)
            for item in data:
                rels = p.search(item.attrs['href'])
                if rels:
                    model, _ = rels.groups()
                    model = model.replace('%2B', '+')
                    if MS and model.lower() not in MS:
                        continue
                    if model not in pats:
                        pats[model] = {}
                    pats[model][__fullversion(ver)] = item.attrs['href']
    except Exception as e:
        # click.echo(f"Error: {e}")
        pass

    print(json.dumps(pats, indent=4))

@cli.command()
@click.option("-p", "--platforms", type=str, help="The platforms of Syno.")
def getmodelsoffline(platforms=None):
    """
    Get Syno Models.
    """
    import json
    import os

    PS = platforms.lower().replace(",", " ").split() if platforms else []

    with open(os.path.join('/mnt/p3/configs', "offline.json")) as user_file:
        data = json.load(user_file)

    models = []
    for item in data["channel"]["item"]:
        if not item["title"].startswith("DSM"):
            continue
        for model in item["model"]:
            arch = model["mUnique"].split("_")[1]
            name = model["mLink"].split("/")[-1].split("_")[1].replace("%2B", "+")
            if PS and arch.lower() not in PS:
                continue
            if not any(m["name"] == name for m in models):
                models.append({"name": name, "arch": arch})

    models = sorted(models, key=lambda k: (k["arch"], k["name"]))
    print(json.dumps(models, indent=4))

if __name__ == "__main__":
    cli()