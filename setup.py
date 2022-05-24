from setuptools import setup, find_packages


with open('README.md') as f:
    readme = f.read()

setup(
    name='Exoswap',
    description='Exoswap Automated Market Maker',
    long_description=readme,
    author='JJ Uzumaki',
    author_email='jjuzumaki@proton.me',
    license=license,
    packages=find_packages(),
    include_package_data=True,
    install_requires=[
        'ethereum',
        'web3',
        'py-solc',
        'pytest'
    ],
)
