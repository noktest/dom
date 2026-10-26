// ==UserScript==
// @name         zasrywacz 3.0
// @match        https://karachan.org/*
// @grant        GM_xmlhttpRequest
// @connect      www.hovno.sk
// @run-at       document-end
// ==/UserScript==


const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms) );

const normURL = url => url.replace(/\/$/, ''); // karachan.org/b/ --> karachan.org/b

function parseTargets(text) {
    const STRIP = /[^a-zA-Z0-9:/?&=#._~%-]/g;
    const URL_START = /^https?:\/\/./;
    const WS = /\s+/;

    const out = [];
    for (const token of text.split(WS)) {
        const t = token.replace(STRIP, '');
        if (URL_START.test(t)) out.push(normURL(t));
    }
    return out;
}


function waitForDocument() {
    return new Promise(resolve => {
        if (document.readyState === 'complete')
            resolve();
        else
            window.addEventListener('load', resolve, { once: true });
        console.log("document loaded")
    });
}


function applyHTML() {
    const menu = document.createElement('div');

    menu.innerHTML = `
        <div class="menu-window" contenteditable="false">
            <div class="menu-section">
                <textarea id="list-of-targets" name="message" rows="6" placeholder="lista linków"></textarea>
                <div class="menu-row">
                    <input type="button" id="add-button" value="dodaj link">
                    <input type="button" id="save-button" value="zapisz">
                    <input type="button" id="clear-button" value="wyczyść">
                </div>
                <div class="menu-row">
                    <label><input type="checkbox" id="sage-checkbox"> saguj</label>
                    <label><input type="checkbox" id="test-checkbox"> test</label>
                </div>
                <div class="menu-row">
                    <input type="button" id="kupa-button" value="kupa">
                    <input type="button" id="cooldown-button" value="cooldown">
                    <input type="button" id="catalog-button" value="katalog">
                </div>
                <input type="button" id="start-button" value="start">
                <div id="count-text"></div>
            </div>
        </div>
    `;

    document.body.appendChild(menu);
}


function applyCSS() {
    const style = document.createElement('style');
    style.textContent = `
    .menu-window {
        position: fixed;
        top: 30%;
        right: 1%;
        z-index: 9999;
        width: 18rem;
        max-width: 90vw;
        box-sizing: border-box;
        font-size: .9rem;
    }
    .menu-section {
        display: flex;
        flex-direction: column;
        gap: 8px;
        padding: 10px;
        border: 1px solid #888;
        border-radius: 4px;
        background: Canvas;
        color: CanvasText;
    }
    .menu-section textarea {
        width: 100%;
        box-sizing: border-box;
        resize: vertical;
        font-size: .8rem;
    }
    .menu-section input[type="button"] {
        font: inherit;
        padding: 4px 8px;
        border-radius: 4px;
        cursor: pointer;
    }
    .menu-row {
        display: flex;
        gap: 8px;
    }
    .menu-row > * {
        flex: 1;
    }
    .menu-section label {
        display: flex;
        align-items: center;
        gap: 4px;
        cursor: pointer;
    }
    #count-text,
    #status-text {
        min-height: 1.2em;
        font-size: .85em;
        opacity: .8;
    }
        `;
    document.head.appendChild(style);
}


function getRandomPictureUrl() {
    const page = Math.floor(Math.random() * 930) + 1;

    console.log("finding a picture")

    return new Promise(resolve => {
        GM_xmlhttpRequest({
            method: 'GET',
            url: `https://www.hovno.sk/galeria?strana=${page}`,
            onload: function (response) {

                const doc = new DOMParser().parseFromString(
                    response.responseText,
                    'text/html'
                );

                const images = doc.querySelectorAll('a.list-group-item.shit img');
                const randomImage = images[Math.floor(Math.random() * images.length)];
                const picture = randomImage.closest('a.list-group-item.shit');
                const title = picture.querySelector('span:not(.badge)').textContent.trim();
                const fullUrl = randomImage.src.replace('/img/thumb/', '/img/full/');

                console.log("picture found");
                console.log(fullUrl);

                resolve({
                    url: fullUrl,
                    title: title
                });
            }
        });
    });
}


function downloadAndSetFile(url, title) {
    const timestamp = Date.now().toString(); // for duplicate evasion

    console.log('setting the picture: "' + title + '"')

    return new Promise((resolve, reject) => {
        GM_xmlhttpRequest({
            method: 'GET',
            url: url,
            responseType: 'blob',
            onload: function (response) {
                if (response.status < 200 || response.status >= 300) {
                    reject(new Error(`download failed, http code: ${response.status}`));
                    return;
                }

                const file = new File(
                    [response.response, new Blob([timestamp])], // appending the bytes
                    title + '.jpg',
                    { type: response.response.type }
                );

                const input = document.querySelector(
                    'input.upload[name="upfile"]'
                );

                if (!input) {
                    reject(new Error('file input not found'));
                    return;
                }

                const dataTransfer = new DataTransfer();
                dataTransfer.items.add(file);

                input.files = dataTransfer.files;
                input.dispatchEvent(new Event('change', { bubbles: true }));

                // pliczek załączony?????
                if (input.files.length > 0 && input.files[0].name === file.name) {
                    console.log("file attached")
                    resolve();
                }
                else reject(new Error('file was not attached'));

            },

            onerror: function () {
                reject(new Error('file download failed'));
            }
        });
    });
}


async function cooldown() {
    const duration = config.boarddata.time_between_posts;
    let elapsed = (Date.now() - Number(localStorage.getItem('lastPostCreatedTime') || 0)) / 1000;
    let remaining = Math.max(0, duration - elapsed) + 1; // +1 just to be safe

    if (remaining <= 1) return; // no need to be safe if there is no cooldown

    while (remaining <= 0) {
        elapsed = (Date.now() - Number(localStorage.getItem('lastPostCreatedTime') || 0)) / 1000;
        remaining = Math.max(0, duration - elapsed);
        console.log("still sending?")
        await sleep(500)
    }

    if (remaining > 0) {
        console.log(`cooldown remaining: ${remaining}s`);
        await sleep(remaining * 1000);
    }

    console.log("cooldown finished")
}


async function catalog() {
    // this utter mess is a sad necessity
    const whereami = new URL(location.href);
    const board = `${whereami.origin}/${whereami.pathname.split('/')[1]}`;
    const base = normURL(board) + '/';
    const url = new URL('catalog.html', base).href;
    let targets = JSON.parse(localStorage.getItem('targets'));

    if (location.href !== url) {
        localStorage.setItem('cataloging', 'true');
        localStorage.setItem('departed', location.href);
        console.log('navigating to catalog:', url);
        location.href = url;
        return;
    }

    console.log("updating the catalog")

    await waitForDocument();
    await sleep(1000);

    const anchors = document.querySelectorAll('.thread a[href^="./res/"]');
    const length = anchors.length;
    const links = new Array(length);
    for (let i = 0; i < length; i++) {
        links[i] = base + anchors[i].getAttribute('href').slice(2);
    }

    localStorage.setItem('catalog', JSON.stringify(links));
    localStorage.setItem('cataloging', 'false');

    // remove 404 threads
    targets = targets.filter(target => links.includes(target));
    localStorage.setItem('targets', JSON.stringify(targets));
    console.log(JSON.stringify(links))

    // let's get back to where we departed from
    location.href = localStorage.getItem('departed')
}



async function zasrywacz(isSage, isTest, board) {

    async function submit(isSage, isTest, creating) {

        async function send(creating) {
            const button = document.querySelector('td.ladda-td button.ladda-button');
            const lastPostTime = Number(localStorage.getItem('lastPostCreatedTime'))

            if (!button) {
                log ('failed to locate the submit button');
                throw new Error('failed to locate the submit button')
                return;
            }

            button.click();

            // if creating a thread, reloading will restart the loop independently of the script
            if (creating) {
                localStorage.setItem('save', 'true') // save the future thread
                while (true) {
                    log("waiting for a reload");
                    await sleep (1000)
                    button.click();
                }
            }
            // when replying, we gotta handle it on our own
            while (lastPostTime === Number(localStorage.getItem('lastPostCreatedTime'))) {
                log("still sending?")
                await sleep(1000)
                button.click();
            }
            return;
        }


        if (isSage) {
            const email = document.querySelector('input[name="email"]');
            if (email) {
                email.value = 'sage';
                log('sage on');
            }
            else {
                log('failed to locate email textarea');
                throw new Error('failed to locate email textarea')
                location.href = board // restarting if zasrywacz ends with an error
                return;
            }
        }


        if (isTest) {
            log('(test mode, not sent)');
            return;
        }


        const { url, title } = await getRandomPictureUrl();
        await downloadAndSetFile(url, title);
        await cooldown();
        await send(creating);
    }

    const log = (...args) => console.log('zasrywacz(): ', ...args);

    const bumps = Number(localStorage.getItem('bumps'));
    const ratio = Number(localStorage.getItem('ratio'));
    let targets = JSON.parse(localStorage.getItem('targets') || '[]');
    const creating = ratio < bumps;
    const dest = creating ? localStorage.getItem('board') : targets[0];

    if (!dest) {
        log(creating ? 'no board set' : 'no targets');
        return;
    }

    const target = new URL(dest, location.href).href;

    await waitForDocument();

    if (normURL(location.href) !== normURL(target)) {
        log(`${normURL(location.href)} !== ${normURL(target)}`)
        log('renavigating to target:', target);

        location.href = target;
        return;
    }
    else log("no need to navigate")


    if (creating) {
        log('creating a thread');
        localStorage.setItem('bumps', 1);
        localStorage.setItem('creating', 'true') // with the reload in mind, we gotta make this info persistent
    }
    else {
        log(`bumping ${bumps} out of ${ratio}`);
        localStorage.setItem('bumps', bumps + 1);
        localStorage.setItem('creating', 'false') // just in case, more robust
    }


    try {
        await submit(isSage, isTest, creating);
    }
    catch (error) {
        const index = targets.indexOf(target);
        log('could not prepare post:', error);
        log('this link is gonna be removed from the list')
        log(target)

        if (index !== -1) targets.splice(index, 1);

        localStorage.setItem('targets', JSON.stringify(targets));

        await sleep(2000)
        location.href = board // restarting
        return;
    }



    // this part of the script will only be executed when bumping a thread.
    // rotate the list of targets and save
    targets.push(targets.shift());
    localStorage.setItem('targets', JSON.stringify(targets));

    // define the next target
    const next = new URL(targets[0], location.href).href;
    log('navigating to next target:', next);
    location.href = next;
    return;
}



async function init() {

    function setTargets(input) {
        const text = Array.isArray(input) ? input.join(' ') : String(input ?? '');
        const boardKey = board ? normURL(board) : null;

        const cleaned = [...new Set(
            parseTargets(text).map(target => target.replace(/(\.html).*$/i, '$1'))
        )].filter(target => normURL(target) !== boardKey);

        localStorage.setItem('targets', JSON.stringify(cleaned));
        targetList.value = cleaned.join(' ');
        countText.textContent = `liczba linków: ${cleaned.length}`;

        console.log(cleaned);
        return cleaned;
    }

    function addTarget(url) {
        return setTargets(`${targetList.value} ${url}`);
    }


    const menu        = document.querySelector('.menu-window');
    const targetList  = menu.querySelector('#list-of-targets');
    const countText   = menu.querySelector('#count-text');
    const sageBox     = menu.querySelector('#sage-checkbox');
    const testBox     = menu.querySelector('#test-checkbox');
    const addButton   = menu.querySelector('#add-button');
    const saveButton  = menu.querySelector('#save-button');
    const clearButton = menu.querySelector('#clear-button');
    const startButton = menu.querySelector('#start-button');

    const board = localStorage.getItem('board');
    let isRunning = localStorage.getItem('isRunning') === 'true';


    setTargets(JSON.parse(localStorage.getItem('targets') || '[]'));
    sageBox.checked = localStorage.getItem('isSage') === 'true';
    testBox.checked = localStorage.getItem('isTest') === 'true';
    startButton.value = isRunning ? 'stop' : 'start';

        // handlers
    menu.querySelector('#kupa-button').addEventListener('click', () => cooldown());
    menu.querySelector('#cooldown-button').addEventListener('click', () => localStorage.setItem('lastPostCreatedTime', Date.now()-10000));
    menu.querySelector('#catalog-button').addEventListener('click', () => catalog());


    addButton.addEventListener('click', () => addTarget(location.href));
    saveButton.addEventListener('click', () => setTargets(targetList.value));
    clearButton.addEventListener('click', () => setTargets([]));

    sageBox.addEventListener('change', () => localStorage.setItem('isSage', sageBox.checked));
    testBox.addEventListener('change', () => localStorage.setItem('isTest', testBox.checked));

    startButton.addEventListener('click', () => {
        isRunning = !isRunning;
        localStorage.setItem('isRunning', isRunning);

        if (isRunning) {
            console.log('started by the user');
            startButton.value = 'stop';
            initializeData();
            zasrywacz(sageBox.checked, testBox.checked, board);
        }
        else {
            console.log('interrupted by the user');
            startButton.value = 'start';
            localStorage.setItem('cataloging', 'false');
            localStorage.setItem('save', 'false');
            location.href = board;
        }
    });


    if (localStorage.getItem('cataloging') === 'true') await catalog();

    if (localStorage.getItem('save') === 'true') {
        console.log(`saving this link: ${location.href}`);
        addTarget(location.href);
        localStorage.setItem('save', 'false');
    }

    if (isRunning) {
        zasrywacz(sageBox.checked, testBox.checked, board);
    }
    else {
        initializeData();
    }
}



function initializeData() {
    const cooldownBump = config.boarddata.time_between_posts;
    const cooldownThread = config.boarddata.time_between_threads;
    const ratio = Math.max(0, Math.ceil(cooldownThread / cooldownBump) - 1);

    const whereami = new URL(location.href);
    const board = `${whereami.origin}/${whereami.pathname.split('/')[1]}`;

    const catalog = JSON.parse(localStorage.getItem('catalog') || '[]')
    const targets = JSON.parse(localStorage.getItem('targets') || '[]')

    const running = localStorage.getItem('isRunning') === 'true';

    if (running) {
        // pre-run sanity check
        if (targets.some(target => !target.startsWith(`${board}/`))) {
            console.log('navigate to your chosen board');
            localStorage.setItem('isRunning', 'false');
            location.href = board;
            return;
        }
        else {
            console.log('all targets are valid')
        }
    }


    console.log("board: "+ board);
    console.log("cooldown for threads: " + cooldownThread + "s, bumps: " + cooldownBump + "s");
    console.log("required ratio: " + ratio + " bumps for every new thread");
    console.log(catalog)

    // initiate states
    localStorage.setItem('ratio', ratio);
    localStorage.setItem('bumps', ratio + 1);
    localStorage.setItem('board', board)
    localStorage.setItem('save', 'false');
    //localStorage.setItem('creating','false')
    //localStorage.setItem('sending', 'false');
    //localStorage.setItem('isRunning', 'false');
    //localStorage.setItem('departed', null);
    //localStorage.setItem('targets', null);
    //localStorage.setItem('cataloging', false);
}



(function main() {
    applyHTML();
    applyCSS();
    init();
})();
