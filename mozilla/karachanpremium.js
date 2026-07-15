// ==UserScript==
// @name         karaczan premium
// @namespace    diskurwy jebać
// @version      2.3.1
// @description  naprawianie matisuby ciąg dalszy
// @match        https://karachan.org/*
// @grant        none
// @run-at       document-end
// ==/UserScript==
//javascript:(()=>{document.querySelectorAll('.file a[download]').forEach(link=>link.click())})(); 
// serwera szanowanie
(function add20mbCheckbox() {
    const row = document.querySelector('tr td label input#spoiler')?.closest('tr');
    if (!row) return;
    const td = row.querySelector('td:last-child');
    if (!td) return;

    const label = document.createElement('label');
    label.innerHTML = `<input id="respect" type="checkbox"> Szanuj serwer`;
    td.appendChild(label);
})();

// duplikaty
(inputs => {
    const baseFiles = new WeakMap();

    function applyPadding(input) {
        const base = baseFiles.get(input);
        if (!base) return;

        const respect = document.querySelector('#respect')?.checked;
        let out = new Uint8Array(base);

        if (respect) {
            const TARGET = 20 * 1024 * 1024;
            if (out.byteLength < TARGET) {
                const padded = new Uint8Array(TARGET);
                padded.set(out);
                out = padded;
            }
        }

        const d = new DataTransfer();
        d.items.add(new File([out], input._origName, { type: input._origType }));
        input.files = d.files;
    }

    inputs.forEach(input => {
        input.addEventListener("change", function () {
            const f = this.files.item(0);
            if (!f) return;

            this._origName = f.name;
            this._origType = f.type;

            // formaty przecwelone
            if (['image/avif', 'image/webp'].includes(f.type)) {
                const c = document.createElement("canvas");
                const ctx = c.getContext("2d");
                const url = URL.createObjectURL(f);
                const im = new Image();
                im.src = url;

                im.onload = () => {
                    c.width = im.width;
                    c.height = im.height;
                    ctx.drawImage(im, 0, 0);
                    c.toBlob(blob => {
                        blob.arrayBuffer().then(buf => {
                            let out = new Uint8Array(buf);

                            // bity randomowe
                            const rand = crypto.getRandomValues(new Uint8Array(8));
                            const extended = new Uint8Array(out.byteLength + rand.length);
                            extended.set(out, 0);
                            extended.set(rand, out.byteLength);

                            baseFiles.set(this, extended);
                            this._origName = f.name.replace(/\.(webp|avif)$/i, ".jpg");
                            this._origType = "image/jpeg";

                            applyPadding(this);
                        });
                        URL.revokeObjectURL(url);
                        c.remove();
                    }, "image/jpeg");
                };
                return;
            }

            // reszta
            if (/\.(jpe?g|png|gif|mp4|webm)$/i.test(f.name)) {
                f.arrayBuffer().then(buf => {
                    let out = new Uint8Array(buf);

                    // bity randomowe
                    const rand = crypto.getRandomValues(new Uint8Array(8));
                    const extended = new Uint8Array(out.byteLength + rand.length);
                    extended.set(out, 0);
                    extended.set(rand, out.byteLength);

                    baseFiles.set(this, extended);
                    applyPadding(this);
                });
            }
        });
    });

    // bo jakiś debil jebany się pruł
    document.querySelector('#respect')?.addEventListener('change', () => {
        inputs.forEach(applyPadding);
    });

})(document.querySelectorAll('input[type="file"]'));

// pobierz fret
(function addInlineDownloadNavButtons() {
    const navDivs = document.querySelectorAll('.navLinks');
    if (!navDivs.length) return;

    navDivs.forEach(nav => {
        const zapisBtn = document.createElement('a');
        zapisBtn.href = 'javascript:;';
        zapisBtn.textContent = 'Pobierz fred';

        const wrapper = document.createDocumentFragment();
        wrapper.appendChild(document.createTextNode('['));
        wrapper.appendChild(zapisBtn);
        wrapper.appendChild(document.createTextNode('] '));

        nav.insertBefore(wrapper, nav.firstChild);

        zapisBtn.addEventListener('click', async () => {
            const files = document.querySelectorAll('.fileText a[download]');
            for (const f of files) {
                const link = document.createElement('a');
                link.href = f.href;
                link.download = f.getAttribute('download') || f.href.split('/').pop();
                document.body.appendChild(link);
                link.click();
                link.remove();
                await new Promise(r => setTimeout(r, 1000));
            }
        });
    });
})();

// obserwowane
(function dimWatchedAfterLoad() {
    const interval = setInterval(() => {
        const spans = document.querySelectorAll('#watched_list .unreadPostsNumber');
        if (!spans.length) return;

        for (const s of spans) {
            if (s.textContent.includes('Ładowanie')) return;
        }

        spans.forEach(s => {
            const count = parseInt(s.textContent.replace(/\D/g, ''), 10);
            if (count === 0) {
                s.closest('li').style.filter = 'brightness(0.5)';
            }
        });
        clearInterval(interval);
    }, 200);
})();

(function IdNTuplesEffect() {
	const applyEffect = elem => {
		const findDepth = (id, depth = 0) => {
			const pos = id.length - depth - 1;
			if(id.charAt(pos) === id.charAt(pos - 1)) {
				return findDepth(id, depth + 1);
			}
			return depth;
		}
		const depth = findDepth(elem.innerText);
		if(depth > 0) {
			const id = elem.innerText;
			const normalText = id.substring(0, id.length - depth - 1);
			const styledText = id.substring(id.length - depth - 1);
			elem.innerHTML = `${normalText}<span style='border: 1px #999999 solid;'>${styledText}</span>`;
		}
	}
	window.addEventListener("load", () => {
		document.querySelectorAll('.quotePost').forEach(applyEffect);
		new MutationObserver(mutations => {
			mutations.forEach(
				m => m.addedNodes.forEach(
					n => applyEffect(n.querySelector('.quotePost'))));
		}).observe(document.querySelector('.thread'), { childList: true });
	});
})();

